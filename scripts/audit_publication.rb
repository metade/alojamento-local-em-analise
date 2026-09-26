#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "json"

PUBLIC_ROOTS = ["data/snapshots/", "data/history/"].freeze
ARTIFACT_ROOTS = ["_site/"].freeze
PRIVATE_PATHS = [
  %r{\Adata_sources/},
  %r{\Adata/private/},
  %r{\Atmp/}
].freeze

# These are deliberately field names and listing URL shapes, rather than broad
# words such as "name" or "address" that also occur in the methodology.
FORBIDDEN_PUBLIC_FIELDS = %w[
  host_id
  listing_id
  listing_url
  latitude
  longitude
  address
  licensa_raw
].freeze
LISTING_URL = %r{https?://[^\s"']+/(?:rooms|users)/}i
AIRBNB_IDENTIFIER = %r{(?:airbnb\.[^\s"']+/(?:rooms|users)/|(?:listing|host)_id\s*[,":])}i
RAW_SOURCE_PATH = %r{(?:data_sources|data/private|tmp)(?:/|\\)}i

def tracked_files
  output, status = Open3.capture2("git", "ls-files", "-z")
  abort "Não foi possível listar os ficheiros Git." unless status.success?

  output.split("\0").reject(&:empty?)
end

def public_file?(path)
  PUBLIC_ROOTS.any? { |root| path.start_with?(root) }
end

def artifact_file?(path)
  ARTIFACT_ROOTS.any? { |root| path.start_with?(root) }
end

def file_text(path)
  File.binread(path).force_encoding("UTF-8")
rescue Errno::ENOENT
  nil
end

def audit_worktree
  errors = []

  tracked_files.each do |path|
    if PRIVATE_PATHS.any? { |pattern| pattern.match?(path) }
      errors << "ficheiro local/detalhado tracked: #{path}"
      next
    end
    next unless public_file?(path) || artifact_file?(path)

    text = file_text(path)
    next unless text

    fields = FORBIDDEN_PUBLIC_FIELDS.select do |field|
      text.lines.first.to_s.split(",").map { |value| value.strip.downcase }.include?(field)
    end
    errors << "campo proibido em #{path}: #{fields.join(', ')}" unless fields.empty?
    errors << "URL de anúncio em #{path}" if text.match?(LISTING_URL)
    errors << "padrão de identificador em #{path}" if text.match?(AIRBNB_IDENTIFIER)
    errors << "referência a fonte local em #{path}" if text.match?(RAW_SOURCE_PATH)

    if artifact_file?(path) && File.basename(path) == "metadata.json"
      begin
        metadata = JSON.parse(text)
        errors << "modo não público em #{path}" unless metadata["mode"] == "public"
      rescue JSON::ParserError
        errors << "metadata inválido em #{path}"
      end
    end
  end

  errors << "atribuição em falta: NOTICE" unless tracked_files.include?("site/NOTICE")

  errors
end

def audit_history
  commits, status = Open3.capture2("git", "rev-list", "--all")
  abort "Não foi possível listar o histórico Git." unless status.success?

  errors = []
  commits.lines.map(&:strip).reject(&:empty?).each do |commit|
    files, file_status = Open3.capture2("git", "ls-tree", "-r", "--name-only", commit)
    abort "Não foi possível ler o commit #{commit}." unless file_status.success?

    files.lines.map(&:strip).each do |path|
      if PRIVATE_PATHS.any? { |pattern| pattern.match?(path) }
        errors << "#{commit[0, 12]} ficheiro detalhado: #{path}"
        next
      end
      next unless public_file?(path)

      text, text_status = Open3.capture2("git", "show", "#{commit}:#{path}")
      next unless text_status.success?

      header = text.lines.first.to_s.split(",").map { |value| value.strip.downcase }
      fields = FORBIDDEN_PUBLIC_FIELDS & header
      errors << "#{commit[0, 12]} campo proibido em #{path}: #{fields.join(', ')}" unless fields.empty?
      errors << "#{commit[0, 12]} URL de anúncio em #{path}" if text.match?(LISTING_URL)
      errors << "#{commit[0, 12]} padrão de identificador em #{path}" if text.match?(AIRBNB_IDENTIFIER)
    end
  end

  errors
end

def audit_artifact(root)
  errors = []
  files = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
  errors << "artefacto vazio: #{root}" if files.empty?

  files.each do |path|
    relative = path.delete_prefix("#{root}/")
    errors << "ficheiro local/bruto no artefacto: #{relative}" if relative.match?(RAW_SOURCE_PATH)
    text = file_text(path)
    next unless text

    header = text.lines.first.to_s.split(",").map { |value| value.strip.downcase }
    fields = FORBIDDEN_PUBLIC_FIELDS & header
    errors << "campo proibido em #{relative}: #{fields.join(', ')}" unless fields.empty?
    errors << "URL de anúncio em #{relative}" if text.match?(LISTING_URL)
    errors << "padrão de identificador em #{relative}" if text.match?(AIRBNB_IDENTIFIER)
    errors << "referência a fonte local em #{relative}" if text.match?(RAW_SOURCE_PATH)

    if File.basename(path) == "metadata.json"
      begin
        metadata = JSON.parse(text)
        errors << "modo não público em #{relative}" unless metadata["mode"] == "public"
      rescue JSON::ParserError
        errors << "metadata inválido em #{relative}"
      end
    end
  end

  notice = File.join(root, "NOTICE")
  errors << "atribuição em falta: #{root}/NOTICE" unless File.file?(notice)
  errors
end

history = ARGV.delete("--history")
artifact = if (index = ARGV.index("--artifact"))
             ARGV.delete_at(index)
             ARGV.delete_at(index)
           end
errors = audit_worktree
errors.concat(audit_history) if history
errors.concat(audit_artifact(artifact)) if artifact

if errors.empty?
  puts history ? "Auditoria da árvore e do histórico: OK" : "Auditoria dos outputs publicáveis: OK"
  exit 0
end

warn history ? "Auditoria da árvore/histórico falhou:" : "Auditoria dos outputs publicáveis falhou:"
errors.uniq.each { |error| warn "- #{error}" }
exit 1
