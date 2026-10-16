require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require_relative "support/pipeline_fixture"
require_relative "support/jekyll_build"

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
      yield root, File.join(root, "public", PipelineFixture::RUN_ID), File.join(root, "private", PipelineFixture::RUN_ID)
    end
  end

  def build(input, destination)
    AlojamentoLocal::ReportPdf.stub(:convert, method(:fake_pdf)) do
      JekyllBuild.build(run_dir: input, destination: destination)
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
          JekyllBuild.build(baseurl: "/different", destination: output)
        end
      end
      assert_equal before, files(root).reject { |key, _| key.start_with?("standalone/", "rendered/") }, "Site builds must preserve snapshot inputs and histories"
      refute File.exist?(File.join(output, "report.html")), "The source page is only published at run routes"
      assert_equal File.binread(File.join(standalone, "report.html")), File.binread(File.join(output, "runs", PipelineFixture::RUN_ID, "report.html"))
    end
  end

  def test_public_report_never_reads_private_diagnostics
    with_runs do |root, public, private_path|
      File.write(File.join(private_path, "listings_detailed.csv"), "invalid diagnostic CSV")
      before = files(private_path)
      output = File.join(root, "report")
      build(public, output)
      assert_equal %w[report.html report.pdf snapshot.json], Dir.children(output).sort
      html = File.read(File.join(output, "report.html"))
      refute_includes html, "host_id"
      refute_includes html, "data_sources/"
      refute_includes html, "al-private-report"
      assert_equal before, files(private_path)
      assert_raises(Errno::ENOENT) { build(private_path, File.join(root, "invalid")) }
    end
  end

  def build_site(root, output, serving: false)
    builder = AlojamentoLocal::SiteData.new(snapshots: File.join(root, "public"),
      distance_history: File.join(root, "public-history", "distance_ranges.csv"),
      outside_region_history: File.join(root, "public-history", "outside_regions.csv"),
      quotes: File.join(PipelineFixture::SOURCES, "quotes.json"))
    AlojamentoLocal::SiteData.stub(:new, builder) do
      AlojamentoLocal::ReportPdf.stub(:convert, method(:fake_pdf)) do
        JekyllBuild.build(destination: output, baseurl: "/local", serving: serving)
      end
    end
  end

  def test_serving_generates_both_reports_from_the_shared_template
    with_runs do |root, public, diagnostics|
      csv_path = File.join(diagnostics, "listings_detailed.csv")
      csv = CSV.read(csv_path, headers: true)
      csv.first["nome"] = '<script>alert("private")</script>'
      File.write(csv_path, csv.to_csv)
      File.write(File.join(diagnostics, "secret.txt"), "Must not be copied")
      before = files(root)
      output = File.join(root, "rendered")
      build_site(root, output, serving: true)
      private_dir = File.join(output, "private-reports", PipelineFixture::RUN_ID)
      assert_equal %w[licence_groups_detailed.csv listings_detailed.csv report.html report.pdf snapshot.json], Dir.children(private_dir).sort
      private_html = File.read(File.join(private_dir, "report.html"))
      public_html = File.read(File.join(output, "runs", PipelineFixture::RUN_ID, "report.html"))
      assert_includes private_html, 'name="al-private-report"'
      assert_includes private_html, "&lt;script&gt;alert(&quot;private&quot;)&lt;/script&gt;"
      refute_includes private_html, '<script>alert("private")</script>'
      assert_includes private_html, "licensa_raw"
      refute_includes public_html, "licensa_raw"
      refute_includes public_html, "al-private-report"
      [private_html, public_html].each { |html| assert_includes html, "34</b>" }
      assert_includes File.read(File.join(output, "index.html")), "/local/private-reports/#{PipelineFixture::RUN_ID}/report.html"
      assert_includes public_html, "/local/private-reports/#{PipelineFixture::RUN_ID}/report.html"
      assert_equal File.binread(File.join(public, "snapshot.json")), File.binread(File.join(private_dir, "snapshot.json"))
      assert_equal before, files(root).reject { |key, _| key.start_with?("rendered/") }
    end
  end

  def test_public_rebuild_cleans_private_files_and_passes_the_publication_audit
    with_runs do |root, _, _|
      output = File.join(root, "rendered")
      audit = [RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", output]
      build_site(root, output, serving: true)
      text, status = Open3.capture2e(*audit)
      refute status.success?
      assert_includes text, "relatório privado"
      build_site(root, output)
      refute Dir.exist?(File.join(output, "private-reports"))
      refute_includes File.read(File.join(output, "index.html")), "/private-reports/"
      text, status = Open3.capture2e(*audit)
      assert status.success?, text
      AlojamentoLocal::SiteChecker.check(output)
    end
  end

  def test_public_build_ignores_invalid_diagnostics_and_serving_skips_incomplete_pairs
    with_runs do |root, _, diagnostics|
      csv_path = File.join(diagnostics, "listings_detailed.csv")
      File.write(csv_path, '"unterminated CSV')
      output = File.join(root, "rendered")
      build_site(root, output)
      refute Dir.exist?(File.join(output, "private-reports"))
      File.delete(csv_path)
      build_site(root, output, serving: true)
      refute Dir.exist?(File.join(output, "private-reports"))
      refute_includes File.read(File.join(output, "index.html")), "/private-reports/"
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

  def test_conversion_failure_stops_the_build_without_modifying_inputs
    with_runs do |root, public, _|
      before = files(public)
      output = File.join(root, "report")
      AlojamentoLocal::ReportPdf.stub(:convert, ->(html, _pdf) {
        assert_equal File.join(output, "report.html"), html
        assert File.file?(html)
        raise "converter failed"
      }) do
        error = assert_raises(RuntimeError) { JekyllBuild.build(run_dir: public, destination: output) }
        assert_equal "converter failed", error.message
      end
      assert_equal before, files(public)
      assert File.file?(File.join(output, "report.html"))
      refute File.exist?(File.join(output, "report.pdf"))
    end
  end
end
