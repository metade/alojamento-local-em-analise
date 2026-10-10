#!/usr/bin/env ruby
# frozen_string_literal: true

# Jekyll is responsible for the editorial site. This boundary script selects
# public analysis runs, prepares Liquid data, and invokes the site generator.

require "csv"
require "fileutils"
require "json"
require_relative "../lib/al_ilegal/registration_metrics"
require_relative "../lib/al_ilegal/overlap"

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
  "localização observada não identificada" => "Localização observada não identificada",
  "número sem correspondência no RNAL" => "Número sem correspondência no RNAL",
  "geografia oficial não identificada" => "Geografia oficial não identificada",
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
  summary["official_registers_lisbon"]
end

def public_runs
  Dir.children(SNAPSHOTS).filter_map do |name|
    path = File.join(SNAPSHOTS, name)
    path if File.directory?(path) && name.match?(/\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}\z/)
  end.sort_by do |path|
    metadata = JSON.parse(File.read(File.join(path, "metadata.json")))
    [metadata.fetch("source_dates").fetch("airbnb_snapshot_date"), metadata.fetch("source_dates").fetch("official_register_download_date"), Gem::Version.new(metadata.fetch("methodology_version")), Gem::Version.new(metadata.fetch("analysis_version"))]
  end.reverse
end

def distance_ranges(run_id, summary)
  return [] unless File.file?(DISTANCE_HISTORY)

  rows = CSV.read(DISTANCE_HISTORY, headers: true).select { |row| row["run_id"] == run_id }
  return [] if rows.empty?

  keys = rows.map { |row| row["range"] }
  raise "Invalid distance ranges for #{run_id}" unless keys.sort == DISTANCE_LABELS.keys.sort &&
    rows.all? { |row| row["distance_method"] == "max_cross_cluster_pair_km_v1" && row["licence_groups"].to_s.match?(/\A\d+\z/) }

  counts = rows.to_h { |row| [row["range"], row["licence_groups"].to_i] }
  expected = summary.fetch("classifications").fetch("licença repetida em várias localizações", 0)
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

def measured_run(runs)
  runs.find do |path|
    metrics = File.join(path, "registration_metrics.json")
    next false unless File.file?(metrics)
    data = JSON.parse(File.read(metrics))
    data["metric_version"] == AlIlegal::RegistrationMetrics::VERSION &&
      data["methodology_version"] == AlIlegal::RegistrationMetrics::SUPPORTED_METHODOLOGY_VERSION
  end || raise("No snapshot has supported measured registration metrics")
end

def site_data(runs)
  run_dir = measured_run(runs)
  run_id = File.basename(run_dir)
  summary = JSON.parse(File.read(File.join(run_dir, "summary.json")))
  metadata = JSON.parse(File.read(File.join(run_dir, "metadata.json")))
  listings = CSV.read(File.join(run_dir, "listings.csv"), headers: true).map(&:to_h)
  freguesias = CSV.read(File.join(run_dir, "freguesias.csv"), headers: true).map(&:to_h)
  grouped = listings.group_by { |row| row["freguesia"] }.transform_values { |rows| counts(rows) }
  ranges = distance_ranges(run_id, summary)
  regions = outside_regions(run_id, listings)
  metrics_path = File.join(run_dir, "registration_metrics.json")
  raise "Missing measured registration metrics for #{run_id}" unless File.file?(metrics_path)
  metrics = JSON.parse(File.read(metrics_path))
  AlIlegal::RegistrationMetrics.validate!(JSON.parse(File.read(metrics_path), symbolize_names: true))
  raise "Metric provenance differs" unless metrics["run_id"] == run_id && metrics["source_files"] == metadata["source_files"] && metrics["methodology_version"] == metadata["methodology_version"]
  measures = metrics.fetch("rows").to_h do |row|
    row["geometry"] = AlIlegal::Overlap.geometry(row["rnal"], row["airbnb"], row["intersection"])
    row["unresolved"] = row["empty_licence"] + row["unrecognised_licence"]
    row["bubble_radius"] = row["announcements"].zero? ? 0 : (85*Math.sqrt(row["unresolved"].to_f/row["announcements"])).round(3)
    [row["geography"], row]
  end
  measures.fetch("Lisboa")["observed_unknown_parish"] = measures.fetch(AlIlegal::Geography::UNKNOWN).fetch("announcements")
  measures.fetch("Lisboa")["official_unknown_parish"] = metrics.fetch("diagnostics").fetch("lisbon_entries_unresolved_parish")
  raise "City announcement count differs" unless summary.fetch("listings") == measures.fetch("Lisboa").fetch("announcements")
  districts = freguesias.reject { |row| row["freguesia"] == AlIlegal::Geography::UNKNOWN }.map do |row|
    raw_name = row["freguesia"]
    measured = measures.fetch(raw_name)
    unless measured.fetch("announcements") == row.fetch("listings").to_i && measured.fetch("identifiable_number") == row.fetch("identifiable_licences").to_i
      raise "District announcement metrics differ: #{raw_name}"
    end
    # Keep the published routes while analysis now uses canonical parish names.
    route_name = AlIlegal::Geography::ALIASES.key(raw_name) || raw_name
    {
      "metrics" => measures.fetch(raw_name),
      "name" => raw_name,
      "display_name" => pretty(raw_name),
      "slug" => route_name.downcase.tr("áàâãäéêëíìîïóôõöúùûüç", "aaaaaeeeiiiioooouuuuc").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-$|\A\z/, ""),
      "listings" => row["listings"].to_i,
      # This snapshot field counts listing rows, not distinct registration numbers.
      "listings_with_identifiable_licence" => row["identifiable_licences"].to_i,
      "establishments_estimate" => row["establishments_estimate"].to_i,
      "categories" => LABELS.filter_map do |key, label|
        value = grouped.dig(raw_name, key)
        value && value["listings"].positive? ? {"key" => key, "label" => label, **value} : nil
      end
    }
  end

  {
    "run_id" => run_id,
    "newer_snapshot_without_metrics" => run_dir == runs.first ? nil : {
      "run_id" => File.basename(runs.first),
      "official_date" => JSON.parse(File.read(File.join(runs.first, "metadata.json"))).fetch("source_dates").fetch("official_register_download_date")
    },
    "metrics" => measures.fetch("Lisboa"),
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

selected = measured_run(runs)
warn "Newest snapshot #{File.basename(runs.first)} lacks supported set metrics; site uses #{File.basename(selected)}" unless selected == runs.first

FileUtils.rm_rf(SITE)
FileUtils.mkdir_p(File.join(SOURCE, "_data"))
File.write(File.join(SOURCE, "_data", "site.json"), JSON.pretty_generate(site_data(runs)))

jekyll = ["bundle", "exec", "jekyll", "build", "--config", File.join(ROOT, "_config.yml")]
jekyll.concat(["--baseurl", ENV["JEKYLL_BASEURL"]]) if ENV["JEKYLL_BASEURL"]
system(*jekyll, chdir: ROOT, exception: true)

runs.each do |source|
  destination = File.join(SITE, "runs", File.basename(source))
  FileUtils.mkdir_p(destination)
  (PUBLIC_FILES + (File.file?(File.join(source, "registration_metrics.json")) ? ["registration_metrics.json"] : [])).each { |file| FileUtils.cp(File.join(source, file), File.join(destination, file)) }
end
FileUtils.cp(File.join(ROOT, "LICENSE"), File.join(SITE, "LICENSE"))
FileUtils.cp(File.join(ROOT, "NOTICE"), File.join(SITE, "NOTICE"))
system("bundle", "exec", "ruby", "scripts/check_site.rb", SITE, chdir: ROOT, exception: true)
system("bundle", "exec", "ruby", "scripts/audit_publication.rb", "--artifact", SITE, chdir: ROOT, exception: true)
puts "Site Jekyll criado em #{SITE} (#{site_data(runs)["districts"].length} freguesias)."
