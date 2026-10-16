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
