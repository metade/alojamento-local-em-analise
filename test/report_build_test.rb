require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "json"
require_relative "support/pipeline_fixture"

class ReportBuildTest < Minitest::Test
  def files(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h { |path| [path.delete_prefix(root + "/"), File.binread(path)] }
  end

  def fake_pdf(_html, pdf)
    File.write(pdf, "%PDF-1.4 simulated")
  end

  def with_runs
    Dir.mktmpdir do |root|
      PipelineFixture.outputs(root)
      yield root, File.join(root, "public", PipelineFixture::RUN_ID), File.join(root, "local", PipelineFixture::RUN_ID)
    end
  end

  def build(input, destination)
    AlojamentoLocal::ReportPdf.stub(:convert, method(:fake_pdf)) do
      AlojamentoLocal::SiteBuilder.new.build(run_dir: input, destination: destination)
    end
  end

  def test_public_report_preserves_inputs_and_renders_counts_and_history
    with_runs do |root, public, _|
      before = files(root)
      destination = File.join(root, "standalone")
      build(public, destination)
      assert_equal %w[report.html report.pdf snapshot.json], Dir.children(destination).sort
      assert_equal before, files(root).reject { |key, _| key.start_with?("standalone/") }
      html = File.read(File.join(destination, "report.html"))
      assert_includes html.gsub(/\s+/, " "), "Não correspondem a anúncios"
      assert_includes html, "incompatível — metodologia diferente"
      assert_includes html, "34</b>"
      assert_includes html, "width:22%" # Four of eighteen licence groups, not 34 announcements.
      # The city metric row must display RNAL, Airbnb and their measured overlap.
      assert_match(/<th>Lisboa<\/th>\s*<td>15<\/td>\s*<td>18<\/td>\s*<td>13<\/td>/, html)
      assert_raises(RuntimeError) { build(public, public) }
      assert_equal before, files(root).reject { |key, _| key.start_with?("standalone/") }
    end
  end

  def test_full_site_generator_and_standalone_render_identical_bytes
    with_runs do |root, public, _|
      standalone = File.join(root, "standalone")
      build(public, standalone)
      output = File.join(root, "rendered")
      data_builder = AlojamentoLocal::SiteData.new(snapshots: File.join(root, "public"),
        distance_history: File.join(root, "public-history", "distance_ranges.csv"),
        outside_region_history: File.join(root, "public-history", "outside_regions.csv"),
        quotes: File.join(PipelineFixture::SOURCES, "quotes.json"))
      before = files(root).reject { |key, _| key.start_with?("standalone/") }
      AlojamentoLocal::SiteData.stub(:new, data_builder) do
        AlojamentoLocal::ReportPdf.stub(:convert, method(:fake_pdf)) do
          AlojamentoLocal::SiteBuilder.new.build(baseurl: "/different", destination: output)
        end
      end
      assert_equal before, files(root).reject { |key, _| key.start_with?("standalone/", "rendered/") }, "Site builds must preserve snapshot inputs and histories"
      refute File.exist?(File.join(output, "report.html")), "The source page is only published at run routes"
      assert_equal File.binread(File.join(standalone, "report.html")), File.binread(File.join(output, "runs", PipelineFixture::RUN_ID, "report.html"))
    end
  end

  def test_schema_four_and_five_reports_preserve_tables_and_definitions
    Dir.mktmpdir do |root|
      input = File.join(root, PipelineFixture::RUN_ID)
      FileUtils.cp_r(File.join(PipelineFixture::ROOT, "legacy_public"), input)
      legacy = File.join(root, "legacy")
      build(input, legacy)
      assert_equal %w[freguesias.csv licence_groups.csv listings.csv metadata.json registration_metrics.json report.html report.pdf summary.json], Dir.children(legacy).sort
      data = JSON.parse(JSON.generate(AlojamentoLocal::PublicSnapshot::Loader.new.load(input).to_h))
      data["schema_version"] = data["metadata"]["output_schema_version"] = "5.0.0"
      File.write(File.join(input, "snapshot.json"), JSON.generate(data))
      %w[metadata.json summary.json registration_metrics.json listings.csv licence_groups.csv freguesias.csv].each { |name| FileUtils.rm(File.join(input, name)) }
      previous = File.join(root, "previous")
      build(input, previous)
      old_html = File.read(File.join(legacy, "report.html")).gsub("metadata.json", "snapshot.json").gsub("registration_metrics.json", "snapshot.json").sub("<dd>4.0.0</dd>", "<dd>5.0.0</dd>")
      assert_equal old_html, File.read(File.join(previous, "report.html"))
      assert_equal %w[report.html report.pdf snapshot.json], Dir.children(previous).sort
    end
  end

  def test_local_snapshot_and_rerun_reports_never_read_diagnostics_or_mutate_inputs
    with_runs do |root, _, local|
      source = File.join(PipelineFixture::SOURCES, "listings-2024-06-01.csv")
      rerun = AlojamentoLocal::Analysis.run(airbnb_path: source, official_path: File.join(PipelineFixture::SOURCES, "official-2024-07-01.csv"), mode: "local", output_root: File.join(root, "local"), history_path: File.join(root, "local-history", "summary.csv"))
      assert_includes rerun[:run_id], "__rerun-"
      File.write(File.join(rerun[:path], "listings_detailed.csv"), "invalid diagnostic CSV")
      before = files(File.join(root, "local"))
      output = File.join(root, "report")
      build(rerun[:path], output)
      assert_equal %w[report.pdf report_local.html], Dir.children(output).sort
      html = File.read(File.join(output, "report_local.html"))
      refute_includes html, "host_id"
      refute_includes html, "data_sources/"
      refute_includes html, 'href="snapshot.json"'
      assert_equal before, files(File.join(root, "local"))
      assert_raises(RuntimeError) { build(local, local) }
      FileUtils.rm(File.join(local, "snapshot.json"))
      File.write(File.join(local, "metadata_local.json"), "{}")
      error = assert_raises(RuntimeError) { build(local, output) }
      assert_includes error.message, "new local analysis rerun"
    end
  end

  def test_invalid_local_snapshot_is_rejected_before_rendering
    with_runs do |root, _, local|
      file = File.join(local, "snapshot.json")
      original = JSON.parse(File.read(file))
      [->(data) { data["schema_version"] = "99" },
        ->(data) { data["licence_group_aggregates"][0]["announcements"] += 1 },
        ->(data) { data["registration_metrics"]["run_id"] = "other" },
        ->(data) { data["registration_metrics"]["source_files"]["airbnb"]["path"] = "different" },
        ->(data) { data["metadata"]["run_id"] = "wrong" },
        ->(data) { data["registration_metrics"]["source_files"]["airbnb"]["sha256"] = "0" * 64 }].each do |mutate|
        data = JSON.parse(JSON.generate(original))
        mutate.call(data)
        File.write(file, JSON.generate(data))
        assert_raises(RuntimeError) { build(local, File.join(root, "output")) }
      end
    end
  end

  def test_missing_history_and_escaped_text_have_explicit_defaults
    with_runs do |root, public, _|
      file = File.join(public, "snapshot.json")
      data = JSON.parse(File.read(file))
      data["summary"].delete("historical_comparisons")
      data["licence_group_aggregates"][0]["official_type"] = '<script>alert("example")</script>'
      File.write(file, JSON.generate(data))
      output = File.join(root, "report")
      build(public, output)
      html = File.read(File.join(output, "report.html"))
      assert_includes html, "Sem runs anteriores."
      assert_includes html, "&lt;script&gt;alert(&quot;example&quot;)&lt;/script&gt;"
      refute_includes html, "<script>"
    end
  end

  def test_unsupported_archive_keeps_existing_report_and_downloads
    Dir.mktmpdir do |root|
      input = File.join(root, PipelineFixture::RUN_ID)
      FileUtils.cp_r(File.join(PipelineFixture::ROOT, "legacy_public"), input)
      FileUtils.rm(File.join(input, "registration_metrics.json"))
      before = files(input)
      error = assert_raises(RuntimeError) { build(input, input) }
      assert_includes error.message, "verified reanalysis"
      assert_equal before, files(input)
    end
  end

  def test_conversion_failure_stops_the_build_without_modifying_inputs
    with_runs do |root, public, _|
      before = files(public)
      output = File.join(root, "report")
      AlojamentoLocal::ReportPdf.stub(:convert, ->(html, _pdf) {
        assert_equal File.join(output, "report.html"), html
        assert File.file?(html)
        raise "converter failed"
      }) do
        error = assert_raises(RuntimeError) { AlojamentoLocal::SiteBuilder.new.build(run_dir: public, destination: output) }
        assert_equal "converter failed", error.message
      end
      assert_equal before, files(public)
      assert File.file?(File.join(output, "report.html"))
      refute File.exist?(File.join(output, "report.pdf"))
    end
  end
end
