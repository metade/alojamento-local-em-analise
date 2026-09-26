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
DISTANCE_HISTORY = File.join(ROOT, "data", "history", "distance_ranges.csv")
OUTSIDE_REGION_HISTORY = File.join(ROOT, "data", "history", "outside_regions.csv")
PUBLIC_FILES = %w[metadata.json summary.json listings.csv licence_groups.csv freguesias.csv report.html].freeze
DISTANCE_LABELS = {
  "500_m_1_km" => "500 m–1 km",
  "1_2_km" => "1–2 km",
  "2_5_km" => "2–5 km",
  "over_5_km" => "Mais de 5 km"
}.freeze
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

def distance_ranges(run_id, summary)
  return [] unless File.file?(DISTANCE_HISTORY)

  rows = CSV.read(DISTANCE_HISTORY, headers: true).select { |row| row["run_id"] == run_id }
  return [] if rows.empty?

  keys = rows.map { |row| row["range"] }
  raise "Invalid distance ranges for #{run_id}" unless keys.sort == DISTANCE_LABELS.keys.sort &&
    rows.all? { |row| row["distance_method"] == "max_cross_cluster_pair_km_v1" && row["licence_groups"].to_s.match?(/\A\d+\z/) }

  counts = rows.to_h { |row| [row["range"], row["licence_groups"].to_i] }
  expected = summary.fetch("classifications").fetch("licença repetida em várias localizações")
  raise "Distance range count differs from licence groups for #{run_id}" unless counts.values.sum == expected

  DISTANCE_LABELS.map { |key, label| {"key" => key, "label" => label, "count" => counts.fetch(key)} }
end

def outside_regions(run_id, listings)
  expected = listings.select { |row| row["classification"] == "licença oficial fora de Lisboa" }
    .sum { |row| row["listings"].to_i }
  return {"rows" => [], "total" => 0, "unresolved_municipality" => 0, "unresolved_region" => 0} if expected.zero?

  raise "Missing outside region counts for #{run_id}" unless File.file?(OUTSIDE_REGION_HISTORY)

  rows = CSV.read(OUTSIDE_REGION_HISTORY, headers: true).select { |row| row["run_id"] == run_id }
  keys = rows.map { |row| [row["resolution"], row["official_region"].to_s.strip] }
  unless rows.any? && keys.uniq.size == keys.size && rows.all? { |row|
    region = row["official_region"].to_s.strip
    resolution = row["resolution"]
    row["region_method"] == "official_register_nutsii_v1" && row["listings"].to_s.match?(/\A[1-9]\d*\z/) &&
      ((resolution == "resolved" && !region.empty?) || (%w[municipality_missing region_missing].include?(resolution) && region.empty?))
  }
    raise "Invalid outside region counts for #{run_id}"
  end

  counts = rows.to_h { |row| [[row["resolution"], row["official_region"].to_s.strip], row["listings"].to_i] }
  raise "Outside region count differs from listings for #{run_id}" unless counts.values.sum == expected

  unresolved_municipality = counts.delete(["municipality_missing", ""]).to_i
  unresolved_region = counts.delete(["region_missing", ""]).to_i
  chart = counts.sort_by { |(_, name), count| [-count, name] }.map { |(_, name), count| {"name" => name, "count" => count} }
  chart << {"name" => "Município não identificado", "count" => unresolved_municipality, "unresolved" => true} if unresolved_municipality.positive?
  chart << {"name" => "Região não identificada", "count" => unresolved_region, "unresolved" => true} if unresolved_region.positive?
  maximum = chart.map { |row| row["count"] }.max
  chart.each do |row|
    row["percent"] = (row["count"] * 100.0 / expected).round(1)
    row["width"] = (row["count"] * 100.0 / maximum).round(1)
  end
  {"rows" => chart, "total" => expected, "unresolved_municipality" => unresolved_municipality, "unresolved_region" => unresolved_region}
end

def site_data(runs)
  run_id = File.basename(runs.first)
  run_dir = runs.first
  summary = JSON.parse(File.read(File.join(run_dir, "summary.json")))
  metadata = JSON.parse(File.read(File.join(run_dir, "metadata.json")))
  listings = CSV.read(File.join(run_dir, "listings.csv"), headers: true).map(&:to_h)
  freguesias = CSV.read(File.join(run_dir, "freguesias.csv"), headers: true).map(&:to_h)
  grouped = listings.group_by { |row| row["freguesia"] }.transform_values { |rows| counts(rows) }
  ranges = distance_ranges(run_id, summary)
  regions = outside_regions(run_id, listings)
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
    "repeated_listings" => listings.select { |row| row["classification"] == "licença repetida em várias localizações" }.sum { |row| row["listings"].to_i },
    "distance_ranges" => ranges,
    "distance_total" => ranges.sum { |range| range["count"] },
    "distance_max" => ranges.map { |range| range["count"] }.max.to_i,
    "outside_regions" => regions,
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
