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

  def test_rejects_unrendered_liquid_in_a_district_page
    with_site do |root|
      File.write(File.join(root, "freguesias/arroios/index.html"), "{{ district.name }}")
      error = assert_raises(RuntimeError) { AlojamentoLocal::SiteChecker.check(root) }
      assert_includes error.message, "Liquid não renderizado"
    end
  end
end
