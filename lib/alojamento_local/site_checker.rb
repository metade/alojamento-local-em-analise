# frozen_string_literal: true

require "find"

module AlojamentoLocal
  class SiteChecker
    def self.check(root)
      required = %w[index.html metodologia.html freguesias/index.html assets/story.css NOTICE LICENSE]
      missing = required.reject { |path| File.file?(File.join(root, path)) }
      raise "Ficheiros obrigatórios em falta: #{missing.join(", ")}" unless missing.empty?
      raise "Fontes CSS copiadas para o artefacto." if Dir.exist?(File.join(root, "assets", "css"))

      district_pages = Dir.glob(File.join(root, "freguesias", "*", "index.html"))
      raise "Nenhuma página de freguesia foi gerada." if district_pages.empty?

      html_files = []
      Find.find(root) { |path| html_files << path if File.file?(path) && File.extname(path) == ".html" }
      unrendered = html_files.select do |path|
        contents = File.read(path)
        contents.include?("{{") || contents.include?("{%")
      end
      raise "Liquid não renderizado em: #{unrendered.join(", ")}" unless unrendered.empty?

      {html_pages: html_files.length, districts: district_pages.length}
    end
  end
end
