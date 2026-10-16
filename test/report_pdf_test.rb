require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require_relative "../lib/alojamento_local"

class ReportPdfTest < Minitest::Test
  def test_converter_receives_completed_html_and_installs_only_successful_pdf
    Dir.mktmpdir do |root|
      html = File.join(root, "report.html")
      pdf = File.join(root, "report.pdf")
      File.write(html, "<!doctype html><p>Relatório completo</p>")
      File.write(pdf, "%PDF-previous")
      [false, "invalid", "empty", true].each do |outcome|
        commands = []
        converter = ->(*command) do
          commands << command
          assert_equal RbConfig.ruby, command[0]
          assert_equal Gem.bin_path("wkhtmltopdf-binary", "wkhtmltopdf"), command[1]
          assert_includes command, "--quiet"
          assert_includes command, "--keep-relative-links"
          assert_equal html, command[-2]
          refute_equal pdf, command[-1]
          assert_includes File.read(command[-2]), "Relatório completo"
          File.write(command[-1], if outcome == "invalid"
            "invalid"
          else
            (outcome == "empty") ? "" : "%PDF-1.4 converted"
          end)
          outcome != false
        end
        AlojamentoLocal::ReportPdf.stub(:system, converter) do
          if outcome == true
            assert_equal pdf, AlojamentoLocal::ReportPdf.convert(html, pdf)
            assert_equal "%PDF-1.4 converted", File.read(pdf)
          else
            error = assert_raises(RuntimeError) { AlojamentoLocal::ReportPdf.convert(html, pdf) }
            assert_includes error.message, html
            assert_includes error.message, "invalid PDF output" if outcome != false
            assert_equal "%PDF-previous", File.read(pdf)
          end
        end
        assert_equal 1, commands.length
        assert_equal %w[report.html report.pdf], Dir.children(root).sort
      end
    end
  end

  def test_conversion_failure_identifies_the_report_and_process_exit_status
    Dir.mktmpdir do |root|
      html = File.join(root, "report.html")
      AlojamentoLocal::ReportPdf.stub(:system, ->(*_command) {
        Kernel.system(RbConfig.ruby, "-e", "exit 23")
      }) do
        error = assert_raises(RuntimeError) do
          AlojamentoLocal::ReportPdf.convert(html, File.join(root, "report.pdf"))
        end
        assert_includes error.message, html
        assert_includes error.message, "exit 23"
      end
      assert_empty Dir.children(root)
    end
  end

  def test_interrupted_conversion_cleans_partial_output
    Dir.mktmpdir do |root|
      pdf = File.join(root, "report.pdf")
      AlojamentoLocal::ReportPdf.stub(:system, ->(*command) {
        File.write(command[-1], "%PDF-partial")
        raise Interrupt
      }) do
        assert_raises(Interrupt) { AlojamentoLocal::ReportPdf.convert(File.join(root, "report.html"), pdf) }
      end
      assert_empty Dir.children(root)
    end
  end
end
