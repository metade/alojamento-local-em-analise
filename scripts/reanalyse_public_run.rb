#!/usr/bin/env ruby
# Recompute verified dated sources, replacing the public date-pair snapshot.
require_relative "../lib/alojamento_local"
run_id = ARGV.fetch(0)
raise ArgumentError, "Expected a public run ID" unless run_id.match?(/\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}(?:__m[\d.]+(?:__a[\d.]+)?)?\z/)
metadata = JSON.parse(File.read(File.join("data/snapshots", run_id, "metadata.json")))
dates = metadata.fetch("source_dates")
airbnb = "data_sources/listings-#{dates.fetch('airbnb_snapshot_date')}.csv"
official = "data_sources/Estabelecimentos_de_Alojamento_Local-#{dates.fetch('official_register_download_date')}.csv"
{"airbnb" => airbnb, "official" => official}.each do |key, path|
  raise "Source bytes differ from selected run: #{key}" unless Digest::SHA256.file(path).hexdigest == metadata.fetch("source_files").fetch(key).fetch("sha256")
end
result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public")
puts "Created #{result[:run_id]} from verified sources of #{run_id}"
puts JSON.pretty_generate(result[:summary])
