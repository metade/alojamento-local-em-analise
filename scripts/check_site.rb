#!/usr/bin/env ruby
# frozen_string_literal: true

require "find"

root = ARGV.fetch(0, "_site")
required = %w[index.html metodologia.html freguesias/index.html assets/story.css NOTICE LICENSE]
missing = required.reject { |path| File.file?(File.join(root, path)) }
abort "Ficheiros obrigatórios em falta: #{missing.join(", ")}" unless missing.empty?
abort "Fontes CSS copiadas para o artefacto." if Dir.exist?(File.join(root, "assets", "css"))

district_pages = Dir.glob(File.join(root, "freguesias", "*", "index.html"))
abort "Nenhuma página de freguesia foi gerada." if district_pages.empty?

html_files = []
Find.find(root) { |path| html_files << path if File.file?(path) && File.extname(path) == ".html" }
unrendered = html_files.select do |path|
  contents = File.read(path)
  contents.include?("{{") || contents.include?("{%")
end
abort "Liquid não renderizado em: #{unrendered.join(", ")}" unless unrendered.empty?

puts "Site verificado: #{html_files.length} páginas HTML, #{district_pages.length} freguesias."
