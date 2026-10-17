#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "json"
require "zlib"
require "stringio"
require_relative "../lib/alojamento_local"

PUBLIC_ROOTS = ["data/snapshots/", "data/history/", "test/fixtures/pipeline/snapshots/", "test/fixtures/pipeline/expected/public/"].freeze
ARTIFACT_ROOTS = ["_site/"].freeze
PRIVATE_PATHS = [
  %r{\Adata_sources/(?!lisboa-freguesias\.geojson\z)},
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
  # Scan ASCII safety patterns in all files, including binary image assets.
  # Forcing a binary file to UTF-8 makes even header parsing raise.
  File.binread(path)
rescue Errno::ENOENT
  nil
end

# Historical safety inspection parses arbitrary JSON without a legacy dataset reader.
def audit_historical_document(text, label)
  errors = []
  begin
    data = JSON.parse(text)
    inspect_keys = lambda do |value|
      case value
      when Hash
        forbidden = value.keys & (FORBIDDEN_PUBLIC_FIELDS + %w[path])
        errors << "campo proibido em #{label}: #{forbidden.join(", ")}" unless forbidden.empty?
        value.each_value { |item| inspect_keys.call(item) }
      when Array
        value.each { |item| inspect_keys.call(item) }
      end
    end
    inspect_keys.call(data)
  rescue => error
    errors << "snapshot inválido em #{label}: #{error.message}"
  end
  errors
end

def audit_pair(path)
  AlojamentoLocal::CandidateDataset.new(File.dirname(path))
  []
rescue => error
  ["snapshot inválido em #{path}: #{error.message}"]
end

def candidate_link_text(text)
  text.gsub(%r{https://www\.airbnb\.com/rooms/[0-9]+(?=["'\s<)>]|$)}, "")
end

def audit_worktree
  errors = []

  (tracked_files + PUBLIC_ROOTS.flat_map { |root| Dir.glob("#{root}**/*").select { |path| File.file?(path) } }).uniq.each do |path|
    if PRIVATE_PATHS.any? { |pattern| pattern.match?(path) }
      errors << "ficheiro local/detalhado tracked: #{path}"
      next
    end
    next unless public_file?(path) || artifact_file?(path)

    text = file_text(path)
    next unless text
    if AlojamentoLocal::CandidateDataset::FILES.include?(File.basename(path))
      errors.concat(audit_pair(path))
      next
    end

    errors << "snapshot obsoleto em #{path}" if File.basename(path) == "snapshot.json"
    fields = FORBIDDEN_PUBLIC_FIELDS.select do |field|
      text.lines.first.to_s.split(",").map { |value| value.strip.downcase }.include?(field)
    end
    errors << "campo proibido em #{path}: #{fields.join(", ")}" unless fields.empty?
    checked_text = candidate_link_text(text)
    errors << "URL de anúncio em #{path}" if checked_text.match?(LISTING_URL)
    errors << "padrão de identificador em #{path}" if checked_text.match?(AIRBNB_IDENTIFIER)
    errors << "referência a fonte local em #{path}" if text.match?(RAW_SOURCE_PATH)
    errors << "relatório privado em #{path}" if text.include?('name="al-private-report"') || text.include?("/private-reports/")
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

      if File.basename(path) == "candidates.json.gz"
        begin
          text = Zlib::GzipReader.new(StringIO.new(text)).read
        rescue => error
          errors << "#{commit[0, 12]} gzip inválido em #{path}: #{error.message}"
          next
        end
      end
      if (AlojamentoLocal::CandidateDataset::FILES + ["snapshot.json"]).include?(File.basename(path))
        errors.concat(audit_historical_document(text, "#{commit[0, 12]} #{path}"))
      end

      header = text.lines.first.to_s.split(",").map { |value| value.strip.downcase }
      fields = FORBIDDEN_PUBLIC_FIELDS & header
      errors << "#{commit[0, 12]} campo proibido em #{path}: #{fields.join(", ")}" unless fields.empty?
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
    if relative.match?(/(?:private-reports|report_data_local|metadata_local|summary_local|detailed|\Aruns\/)/)
      errors << "dados privados no artefacto: #{relative}"
    end
    text = file_text(path)
    next unless text
    if AlojamentoLocal::CandidateDataset::FILES.include?(File.basename(path))
      errors.concat(audit_pair(path))
      next
    end

    errors << "snapshot obsoleto em #{relative}" if File.basename(path) == "snapshot.json"
    header = text.lines.first.to_s.split(",").map { |value| value.strip.downcase }
    fields = FORBIDDEN_PUBLIC_FIELDS & header
    errors << "campo proibido em #{relative}: #{fields.join(", ")}" unless fields.empty?
    checked_text = candidate_link_text(text)
    errors << "URL de anúncio em #{relative}" if checked_text.match?(LISTING_URL)
    errors << "padrão de identificador em #{relative}" if checked_text.match?(AIRBNB_IDENTIFIER)
    errors << "referência a fonte local em #{relative}" if text.match?(RAW_SOURCE_PATH)
    errors << "relatório privado em #{relative}" if text.include?('name="al-private-report"') || text.include?("/private-reports/")
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
