#!/usr/bin/env ruby
require "csv"
require "json"
require_relative "../lib/alojamento_local"

run_dir = ARGV.fetch(0) { abort "Usage: ruby scripts/regenerate_public_report.rb RUN_DIR" }
metadata = JSON.parse(File.read(File.join(run_dir, "metadata.json")), symbolize_names: true)
summary = JSON.parse(File.read(File.join(run_dir, "summary.json")), symbolize_names: true)
groups = CSV.read(File.join(run_dir, "licence_groups.csv"), headers: true).map { |row| row.to_h.transform_keys(&:to_sym) }
freguesias = CSV.read(File.join(run_dir, "listings.csv"), headers: true).map { |row| row.to_h.transform_keys(&:to_sym) }

report = AlojamentoLocal::Report.html(metadata, summary, groups, freguesias)
report = report.sub("</body></html>", AlojamentoLocal::Report.historical_section(summary) + "</body></html>")
File.write(File.join(run_dir, "report.html"), report)
puts "Regenerated #{File.join(run_dir, 'report.html')}"
