#!/usr/bin/env ruby
# frozen_string_literal: true

# Jekyll is responsible for the editorial site. This boundary script selects
# public analysis runs, prepares Liquid data, and invokes the site generator.

require "csv"
require "fileutils"
require "json"

ROOT = File.expand_path("..", __dir__)
SNAPSHOTS = File.join(ROOT, "data", "snapshots")
SOURCE = File.join(ROOT, "site")
SITE = File.join(ROOT, "_site")
QUOTES = File.join(ROOT, "site_content", "quotes.json")
PUBLIC_FILES = %w[metadata.json summary.json listings.csv licence_groups.csv freguesias.csv report.html].freeze
LABELS = {
  "sem licença" => "Sem licença",
  "sem licença identificável" => "Sem licença identificável",
  "licença repetida em várias localizações" => "Licença repetida em diferentes localizações",
  "licença oficial fora de Lisboa" => "Licença registada fora de Lisboa",
  "licença única em Lisboa" => "Licença única em Lisboa",
  "provável estabelecimento com anúncios múltiplos" => "Provável estabelecimento com anúncios múltiplos",
  "licença repetida na mesma localização" => "Licença repetida na mesma localização"
}.freeze

def pretty(value)
  {
    "Alcntara" => "Alcântara", "Belm" => "Belém", "Misericrdia" => "Misericórdia",
    "Parque das Naes" => "Parque das Nações", "Penha de Frana" => "Penha de França",
    "Santo Antnio" => "Santo António", "So Domingos de Benfica" => "São Domingos de Benfica",
    "So Vicente" => "São Vicente"
  }.fetch(value.to_s, value.to_s)
end

def counts(rows)
  rows.each_with_object(Hash.new { |h, k| h[k] = {"listings" => 0, "licences" => 0, "estimate" => 0} }) do |row, out|
    value = out[row["classification"]]
    value["listings"] += row["listings"].to_i
    value["licences"] += row["identifiable_licences"].to_i
    value["estimate"] += row["establishments_estimate"].to_i
  end
end

def official_count(summary, run_id)
  return summary["official_registers_lisbon"] if summary["official_registers_lisbon"]

  date = run_id[/__([0-9-]+)\z/, 1]
  path = Dir[File.join(ROOT, "data_sources", "Estabelecimentos_de_Alojamento_Local-*.csv")]
    .select { |candidate| candidate[/-(\d{4}-\d{2}-\d{2})\.csv\z/, 1].to_s <= date.to_s }
    .max_by { |candidate| candidate[/-(\d{4}-\d{2}-\d{2})\.csv\z/, 1].to_s }
  return nil unless path

  CSV.foreach(path, headers: true).count { |row| row["Concelho"] == "Lisboa" }
end

def public_runs
  Dir.children(SNAPSHOTS).filter_map do |name|
    path = File.join(SNAPSHOTS, name)
    path if File.directory?(path)
  end.sort.reverse
end

def site_data(runs)
  run_id = File.basename(runs.first)
  run_dir = runs.first
  summary = JSON.parse(File.read(File.join(run_dir, "summary.json")))
  metadata = JSON.parse(File.read(File.join(run_dir, "metadata.json")))
  listings = CSV.read(File.join(run_dir, "listings.csv"), headers: true).map(&:to_h)
  freguesias = CSV.read(File.join(run_dir, "freguesias.csv"), headers: true).map(&:to_h)
  grouped = listings.group_by { |row| row["freguesia"] }.transform_values { |rows| counts(rows) }
  districts = freguesias.map do |row|
    raw_name = row["freguesia"]
    {
      "name" => raw_name,
      "display_name" => pretty(raw_name),
      "slug" => raw_name.downcase.tr("áàâãäéêëíìîïóôõöúùûüç", "aaaaaeeeiiiioooouuuuc").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-$|\A\z/, ""),
      "listings" => row["listings"].to_i,
      "establishments_estimate" => row["establishments_estimate"].to_i,
      "categories" => LABELS.filter_map do |key, label|
        value = grouped.dig(raw_name, key)
        value ? {"key" => key, "label" => label, **value} : nil
      end
    }
  end

  {
    "run_id" => run_id,
    "summary" => summary,
    "metadata" => metadata,
    "official_count" => official_count(summary, run_id),
    "listings" => listings,
    "districts" => districts,
    "labels" => LABELS.values,
    "quotes" => File.exist?(QUOTES) ? JSON.parse(File.read(QUOTES)) : [],
    "runs" => runs.map { |path| File.basename(path) }
  }
end

runs = public_runs
abort "Não existem snapshots públicos em #{SNAPSHOTS}." if runs.empty?

FileUtils.rm_rf(SITE)
FileUtils.mkdir_p(File.join(SOURCE, "_data"))
File.write(File.join(SOURCE, "_data", "site.json"), JSON.pretty_generate(site_data(runs)))

jekyll = ["bundle", "exec", "jekyll", "build", "--config", File.join(ROOT, "_config.yml")]
jekyll.concat(["--baseurl", ENV["JEKYLL_BASEURL"]]) if ENV["JEKYLL_BASEURL"]
system(*jekyll, chdir: ROOT, exception: true)

runs.each do |source|
  destination = File.join(SITE, "runs", File.basename(source))
  FileUtils.mkdir_p(destination)
  PUBLIC_FILES.each { |file| FileUtils.cp(File.join(source, file), File.join(destination, file)) }
end
FileUtils.cp(File.join(ROOT, "LICENSE"), File.join(SITE, "LICENSE"))
FileUtils.cp(File.join(ROOT, "NOTICE"), File.join(SITE, "NOTICE"))
system("npm", "run", "site:css", chdir: ROOT, exception: true)
system("bundle", "exec", "ruby", "scripts/check_site.rb", SITE, chdir: ROOT, exception: true)
system("bundle", "exec", "ruby", "scripts/audit_publication.rb", "--artifact", SITE, chdir: ROOT, exception: true)
puts "Site Jekyll criado em #{SITE} (#{site_data(runs)["districts"].length} freguesias)."
