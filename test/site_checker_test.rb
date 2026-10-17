require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/alojamento_local"

class SiteCheckerTest < Minitest::Test
  def with_site
    Dir.mktmpdir("site-checker-") do |root|
      %w[index.html metodologia.html freguesias/index.html freguesias/arroios/index.html assets/story.css NOTICE LICENSE].each do |file|
        path = File.join(root, file)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "rendered")
      end
      yield root
    end
  end

  def test_returns_counts_for_a_complete_site
    with_site do |root|
      assert_equal({html_pages: 4, districts: 1}, AlojamentoLocal::SiteChecker.check(root))
    end
  end

  def test_rejects_a_site_without_compiled_css
    with_site do |root|
      FileUtils.rm(File.join(root, "assets/story.css"))
      error = assert_raises(RuntimeError) { AlojamentoLocal::SiteChecker.check(root) }
      assert_includes error.message, "assets/story.css"
    end
  end

  def test_report_outputs_and_dated_download_links
    with_site do |root|
      path = File.join(root, "snapshots", "2024-06-01__2024-07-01")
      FileUtils.mkdir_p(path)
      File.write(File.join(root, "index.html"), '<a href="/base/snapshots/2024-06-01__2024-07-01/snapshot.json">download</a>')
      assert_raises(RuntimeError) { AlojamentoLocal::SiteChecker.check(root) }
      File.write(File.join(path, "snapshot.json"), "{}")
      File.write(File.join(root, "index.html"), '<a href="/base/report.html">report</a>')
      assert_raises(RuntimeError) { AlojamentoLocal::SiteChecker.check(root) }
      html = File.join(root, "report.html")
      File.write(html, '<a href="snapshots/2024-06-01__2024-07-01/snapshot.json">Dados</a>')
      File.write(File.join(root, "report.pdf"), "invalid")
      assert_raises(RuntimeError) { AlojamentoLocal::SiteChecker.check(root) }
      File.write(File.join(root, "report.pdf"), "%PDF-test")
      assert_equal 5, AlojamentoLocal::SiteChecker.check(root).fetch(:html_pages)
      File.write(html, '<a href="missing.json">Dados</a>')
      assert_raises(RuntimeError) { AlojamentoLocal::SiteChecker.check(root) }
    end
  end

  def test_requires_expected_reports_even_when_no_report_page_was_written
    with_site do |root|
      assert_raises(RuntimeError) do
        AlojamentoLocal::SiteChecker.check(root, required: AlojamentoLocal::SiteChecker::REQUIRED_FILES + ["report.html", "report.pdf"])
      end
    end
  end
end
