require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "rake"
require "open3"
require "open-uri"
require_relative "../lib/alojamento_local"

class AnalysisFlowsTest < Minitest::Test
  def test_invalid_options_fail_before_selecting_sources
    AlojamentoLocal::Analysis::Data.stub(:local_paths!, -> { flunk "Invalid options must not select sources" }) do
      assert_raises(ArgumentError) { AlojamentoLocal::Analysis.run(mode: "unknown") }
      assert_raises(ArgumentError) { AlojamentoLocal::Analysis.run(airbnb_path: "airbnb.csv") }
      assert_raises(ArgumentError) { AlojamentoLocal::Analysis.run(official_path: "official.csv") }
    end
  end

  def with_sources
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data_sources"))
      sources = File.expand_path("fixtures/pipeline/sources", __dir__)
      FileUtils.cp(File.join(sources, "listings-2024-06-01.csv"), File.join(root, "data_sources"))
      FileUtils.cp(File.join(sources, "official-2024-07-01.csv"),
        File.join(root, "data_sources", "Estabelecimentos_de_Alojamento_Local-2024-07-01.csv"))
      git_metadata = ->(*command) do
        case command
        when ["git", "rev-parse", "HEAD"] then ["a" * 40, nil]
        when ["git", "status", "--porcelain", "--untracked-files=no"] then ["", nil]
        else flunk "Unexpected metadata command: #{command.inspect}"
        end
      end
      Open3.stub(:capture2, git_metadata) { Dir.chdir(root) { yield } }
    end
  end

  def test_public_analysis_recalculates_without_downloads_and_preserves_hash_guard
    with_sources do
      URI.stub(:open, ->(*) { flunk "Analysis must not download sources" }) do
        first = AlojamentoLocal::Analysis.run
        snapshot = File.join(first[:path], "snapshot.json")
        archived = {"report.html" => "archived public report", "report.pdf" => "%PDF-archived"}
        archived.each { |file, content| File.binwrite(File.join(first[:path], file), content) }
        repeated = AlojamentoLocal::Analysis.run
        assert_equal first[:path], repeated[:path]
        archived.each { |file, content| assert_equal content, File.binread(File.join(first[:path], file)) }
        assert_equal 1, CSV.read("data/history/summary.csv", headers: true).length
        before = File.binread(snapshot)
        File.write("data_sources/Estabelecimentos_de_Alojamento_Local-2024-07-01.csv", "changed bytes")
        error = assert_raises(RuntimeError) { AlojamentoLocal::Analysis.run }
        assert_includes error.message, "Source hashes differ"
        assert_equal before, File.binread(snapshot)
      end
    end
  end

  def test_reanalysis_replaces_public_and_private_outputs_together
    with_sources do
      first = AlojamentoLocal::Analysis.run
      File.write(File.join(first[:private_path], "obsolete.txt"), "outdated")
      repeated = AlojamentoLocal::Analysis.run
      assert_equal first[:path], repeated[:path]
      assert_equal first[:private_path], repeated[:private_path]
      assert_equal %w[licence_groups_detailed.csv listings_detailed.csv], Dir.children(repeated[:private_path]).sort
      assert_equal ["snapshot.json"], Dir.children(repeated[:path])
      assert_equal 1, CSV.read("data/history/summary.csv", headers: true).length
      refute Dir.exist?("data/private/history")
    end
  end

  def test_source_mutation_during_analysis_preserves_outputs_and_history
    with_sources do
      AlojamentoLocal::Analysis.run
      before = analysis_files
      metrics = AlojamentoLocal::Analysis::RegistrationMetrics
      calculate = metrics.method(:calculate)
      mutate_source = ->(*arguments) do
        result = calculate.call(*arguments)
        File.open("data_sources/listings-2024-06-01.csv", "a") { |file| file.write("\n") }
        result
      end

      error = metrics.stub(:calculate, mutate_source) do
        assert_raises(RuntimeError) { AlojamentoLocal::Analysis.run }
      end
      assert_equal "Source bytes changed during analysis", error.message
      assert_equal before, analysis_files
    end
  end

  def test_invalid_staged_snapshot_preserves_publication_and_cleans_staging
    with_sources do
      AlojamentoLocal::Analysis.run
      before = analysis_files
      write_file = File.method(:write)
      corrupt_snapshot = ->(path, content, *arguments, **options) do
        if File.basename(path) == "snapshot.json"
          document = JSON.parse(content)
          document.fetch("summary")["listings"] = -1
          content = JSON.generate(document)
        end
        write_file.call(path, content, *arguments, **options)
      end

      File.stub(:write, corrupt_snapshot) do
        assert_raises(RuntimeError) { AlojamentoLocal::Analysis.run }
      end
      assert_equal before, analysis_files
      assert_empty Dir.glob("data/snapshots/.analysis-*")
    end
  end

  def test_diagnostics_failure_preserves_all_previous_outputs
    with_sources do
      AlojamentoLocal::Analysis.run
      before = analysis_files
      CSV.stub(:open, ->(*) { raise "diagnostic CSV failed" }) do
        assert_raises(RuntimeError) { AlojamentoLocal::Analysis.run }
      end
      assert_equal before, analysis_files
      assert_empty Dir.glob("data/snapshots/.analysis-*")
    end
  end

  def test_private_destinations_cannot_overlap_public_outputs
    with_sources do
      %w[data/snapshots data/history site _site].each do |private_root|
        assert_raises(ArgumentError) { AlojamentoLocal::Analysis.run(private_root: private_root) }
      end
      refute Dir.exist?("data/snapshots")
    end
  end

  def analysis_files
    Dir.glob("data/**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h do |path|
      [path, File.binread(path)]
    end
  end

  def with_analysis_task
    Rake.with_application do
      load File.expand_path("../Rakefile", __dir__)
      URI.stub(:open, ->(*) { flunk "Analysis task must not download sources" }) do
        yield Rake::Task["analysis"]
      end
    end
  end

  def test_analysis_task_selects_verified_snapshot_sources_and_preserves_other_runs
    with_analysis_task do |task|
      with_sources do
        selected = AlojamentoLocal::Analysis.run
        snapshot_path = File.join(selected[:path], "snapshot.json")
        snapshot = JSON.parse(File.read(snapshot_path))
        snapshot.fetch("metadata")["analysis_version"] = "0.0.1"
        File.write(snapshot_path, JSON.generate(snapshot))
        archived = {"report.html" => "archived public report", "report.pdf" => "%PDF-archived"}
        archived.each { |file, bytes| File.binwrite(File.join(selected[:path], file), bytes) }
        File.write(File.join(selected[:private_path], "obsolete.txt"), "obsolete")

        FileUtils.cp("data_sources/listings-2024-06-01.csv", "data_sources/listings-2024-08-01.csv")
        FileUtils.cp("data_sources/Estabelecimentos_de_Alojamento_Local-2024-07-01.csv",
          "data_sources/Estabelecimentos_de_Alojamento_Local-2024-09-01.csv")
        unrelated = AlojamentoLocal::Analysis.run
        before = analysis_files
        histories = Dir.glob("data/history/*.csv").to_h do |path|
          [path, CSV.read(path, headers: true).reject { |row| row["run_id"] == selected[:run_id] }.map(&:to_h)]
        end

        AlojamentoLocal::Analysis::Data.stub(:local_paths!, -> { flunk "Explicit run must use its recorded dates" }) do
          capture_io { task.invoke(selected[:run_id]) }
        end

        updated = AlojamentoLocal::PublicSnapshot.load(selected[:path])
        assert_equal selected[:run_id], updated.dig("metadata", "run_id")
        assert_equal AlojamentoLocal::ANALYSIS_VERSION, updated.dig("metadata", "analysis_version")
        assert_equal AlojamentoLocal::METHODOLOGY_VERSION, updated.dig("metadata", "methodology_version")
        %w[source_dates source_files].each do |key|
          assert_equal snapshot.dig("metadata", key), updated.dig("metadata", key)
        end
        archived.each { |file, bytes| assert_equal bytes, File.binread(File.join(selected[:path], file)) }
        refute File.exist?(File.join(selected[:private_path], "obsolete.txt"))
        unrelated_files = ->(files) { files.select { |path, _| path.include?(unrelated[:run_id]) } }
        assert_equal unrelated_files.call(before), unrelated_files.call(analysis_files)
        histories.each do |path, rows|
          assert_equal rows, CSV.read(path, headers: true).reject { |row| row["run_id"] == selected[:run_id] }.map(&:to_h)
          assert_equal 2, CSV.read(path, headers: true).map { |row| row["run_id"] }.uniq.size
        end
      end
    end
  end

  def test_analysis_task_rejects_invalid_and_unknown_run_ids_before_analysis
    with_analysis_task do |task|
      with_sources do
        AlojamentoLocal::Analysis.run
        before = analysis_files
        AlojamentoLocal::Analysis.stub(:run, ->(**) { flunk "Invalid run must fail before analysis" }) do
          ["invalid", "../2024-06-01__2024-07-01", "2024-01-01__2024-02-01"].each do |run_id|
            task.reenable
            error = assert_raises(ArgumentError, RuntimeError) { task.invoke(run_id) }
            assert_match(/(?:Invalid|Unknown) public run ID/, error.message)
            assert_equal before, analysis_files
          end
        end
      end
    end
  end

  def test_analysis_task_validates_snapshot_before_analysis
    with_analysis_task do |task|
      with_sources do
        selected = AlojamentoLocal::Analysis.run
        File.write(File.join(selected[:path], "snapshot.json"), "{}")
        before = analysis_files
        AlojamentoLocal::Analysis.stub(:run, ->(**) { flunk "Invalid snapshot must fail before analysis" }) do
          error = assert_raises(RuntimeError) { task.invoke(selected[:run_id]) }
          assert_includes error.message, "Invalid snapshot schema"
        end
        assert_equal before, analysis_files
      end
    end
  end

  def test_analysis_task_checks_both_source_hashes_and_missing_files_before_analysis
    with_analysis_task do |task|
      with_sources do
        selected = AlojamentoLocal::Analysis.run
        before = analysis_files
        AlojamentoLocal::Analysis.stub(:run, ->(**) { flunk "Unverified sources must fail before analysis" }) do
          Dir.glob("data_sources/*.csv").each do |path|
            bytes = File.binread(path)
            File.binwrite(path, bytes + "\n")
            task.reenable
            error = assert_raises(RuntimeError) { task.invoke(selected[:run_id]) }
            assert_includes error.message, "Source bytes differ from selected run"
            assert_includes error.message, path
            assert_equal before, analysis_files

            File.delete(path)
            task.reenable
            error = assert_raises(RuntimeError) { task.invoke(selected[:run_id]) }
            assert_includes error.message, "Missing source"
            assert_includes error.message, path
            assert_equal before, analysis_files
            File.binwrite(path, bytes)
          end
        end
      end
    end
  end

  def test_cascading_tasks_and_independent_stages
    rakefile = File.expand_path("../Rakefile", __dir__)
    Rake.with_application do
      load rakefile
      calls = []
      %w[sources:update analysis site:build].each do |name|
        Rake::Task[name].clear_actions.enhance { calls << name }
      end
      {"refresh" => %w[sources:update analysis site:build],
       "rebuild" => %w[analysis site:build],
       "analysis" => %w[analysis],
       "sources:update" => %w[sources:update],
       "site:build" => %w[site:build]}.each do |entry, expected|
        Rake.application.tasks.each(&:reenable)
        calls.clear
        Rake::Task[entry].invoke
        assert_equal expected, calls, entry
      end
    end
  end

  def test_force_is_read_only_by_the_source_update_task
    previous_force = ENV["FORCE"]
    ENV["FORCE"] = "1"
    Rake.with_application do
      load File.expand_path("../Rakefile", __dir__)
      updates = 0
      update = ->(**options) do
        assert_equal({force: true}, options)
        updates += 1
        %w[airbnb.csv official.csv]
      end
      AlojamentoLocal::Analysis::Data.stub(:update!, update) do
        capture_io { Rake::Task["sources:update"].invoke }
      end
      assert_equal 1, updates
      Rake::Task["site:build"].clear_actions
      with_sources do
        URI.stub(:open, ->(*) { flunk "Forced rebuild must not download sources" }) do
          AlojamentoLocal::Analysis::Data.stub(:update!, ->(**) { flunk "Rebuild must not update sources" }) do
            capture_io { Rake::Task["rebuild"].invoke }
            assert File.file?("data/snapshots/2024-06-01__2024-07-01/snapshot.json")
          end
        end
      end
    end
  ensure
    ENV["FORCE"] = previous_force
  end
end
