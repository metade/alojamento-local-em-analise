# frozen_string_literal: true

require "tempfile"
require "fileutils"
require "rbconfig"

module AlojamentoLocal
  class ReportPdf
    def self.valid?(path)
      File.file?(path) && File.size(path) > 5 && File.binread(path, 5) == "%PDF-"
    end

    def self.convert(html, destination)
      temporary = Tempfile.new(["report-", ".pdf"], File.dirname(destination))
      begin
        temporary.close
        executable = Gem.bin_path("wkhtmltopdf-binary", "wkhtmltopdf")
        success = system(RbConfig.ruby, executable, "--quiet", "--keep-relative-links", "--print-media-type", "--orientation", "Landscape", File.expand_path(html), temporary.path)
        raise "wkhtmltopdf PDF conversion failed or produced an invalid PDF." unless success && valid?(temporary.path)
        FileUtils.mv(temporary.path, destination)
        destination
      ensure
        temporary.close!
      end
    end
  end
end
