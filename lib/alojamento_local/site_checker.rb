# frozen_string_literal: true

require "cgi"

module AlojamentoLocal
  class SiteChecker
    REQUIRED_FILES = %w[index.html metodologia.html freguesias/index.html assets/story.css NOTICE LICENSE].freeze

    def self.check(root, required: REQUIRED_FILES)
      missing = required.reject { |path| File.file?(File.join(root, path)) }
      raise "Ficheiros obrigatórios em falta: #{missing.join(", ")}" unless missing.empty?
      raise "Fontes CSS copiadas para o artefacto." if Dir.exist?(File.join(root, "assets", "css"))

      district_pages = Dir.glob(File.join(root, "freguesias", "*", "index.html"))
      raise "Nenhuma página de freguesia foi gerada." if required.include?("freguesias/index.html") && district_pages.empty?

      html_files = Dir.glob(File.join(root, "**", "*.html"))
      html_files.each do |path|
        text = File.read(path)
        report = File.basename(path) == "report.html"
        if report
          pdf = File.join(File.dirname(path), "report.pdf")
          raise "Missing or invalid report PDF: #{pdf}" unless ReportPdf.valid?(pdf)
        end
        text.scan(/href=["']([^"']+)["']/).flatten.each do |href|
          next if href.match?(%r{\Ahttps?://}) || href.start_with?("#")
          route = CGI.unescapeHTML(href).split(/[?#]/).first
          candidate_route = route&.match(%r{/(?:snapshots/[^/]+/(?:summary\.json|candidates\.json\.gz)|report\.(?:html|pdf))\z})
          target = if candidate_route
            File.join(root, candidate_route[0].delete_prefix("/"))
          elsif report && route && !route.start_with?("/")
            File.expand_path(route, File.dirname(path))
          end
          raise "Unresolved report download: #{href}" if target && !File.file?(target)
        end
      end
      {html_pages: html_files.length, districts: district_pages.length}
    end
  end
end
