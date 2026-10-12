#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds only the public aggregate for an existing immutable run. Raw sources
# must match the hashes already recorded in that run's metadata.
require "csv"
require "digest"
require "json"
require_relative "../lib/alojamento_local"

root = File.expand_path("..", __dir__)
run_id = ARGV.fetch(0)
run_dir = File.join(root, "data", "snapshots", run_id)
loader = AlojamentoLocal::PublicSnapshot::Loader.new
metadata = loader.metadata(run_dir)
snapshot = loader.load(run_dir) if %w[4.0.0 5.0.0].include?(metadata.fetch("output_schema_version"))
# Unmeasured historical schemas predate the shared loader; keep this archive
# utility available for them without consulting exports of consolidated runs.
summary = snapshot ? snapshot.summary : JSON.parse(File.read(File.join(run_dir, "summary.json")))
raise "Run ID mismatch" unless metadata.fetch("run_id") == run_id && summary.fetch("run_id") == run_id

airbnb_date = metadata.dig("source_dates", "airbnb_snapshot_date")
official_date = metadata.dig("source_dates", "official_register_download_date")
airbnb = File.join(root, "data_sources", "listings-#{airbnb_date}.csv")
official = File.join(root, "data_sources", "Estabelecimentos_de_Alojamento_Local-#{official_date}.csv")
{"airbnb" => airbnb, "official" => official}.each do |source, path|
  expected = metadata.dig("source_files", source, "sha256")
  raise "Source hash mismatch: #{source}" unless Digest::SHA256.file(path).hexdigest == expected
end

listings, = AlojamentoLocal::Analysis.analyse(airbnb, official)
repeated = listings.select { |row| row[:license_group_assessment] == "licença repetida em várias localizações" }
public_rows = snapshot ? snapshot.published_announcement_rows : CSV.read(File.join(run_dir, "listings.csv"), headers: true)
public_count = public_rows
  .select { |row| row["classification"] == "licença repetida em várias localizações" }
  .sum { |row| row["listings"].to_i }
raise "Announcement count mismatch" unless repeated.size == public_count

counts = AlojamentoLocal::Analysis.distance_range_counts(listings)
raise "Licence group count mismatch" unless counts.values.sum == summary.fetch("classifications").fetch("licença repetida em várias localizações")

path = File.join(root, "data", "history", "distance_ranges.csv")
AlojamentoLocal::Analysis.append_distance_history(path, run_id, listings)
puts "#{run_id}: #{counts.values.sum} números de licença / #{repeated.size} anúncios; #{counts.inspect}"
