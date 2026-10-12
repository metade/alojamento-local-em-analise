#!/usr/bin/env ruby
require "csv"
require "json"
require_relative "../lib/alojamento_local"

run_dir = ARGV.fetch(0) { abort "Usage: ruby scripts/regenerate_public_report.rb RUN_DIR" }
metadata = JSON.parse(File.read(File.join(run_dir, "metadata.json")), symbolize_names: true)
summary = JSON.parse(File.read(File.join(run_dir, "summary.json")), symbolize_names: true)
begin
  metrics = JSON.parse(File.read(File.join(run_dir, "registration_metrics.json")), symbolize_names: true)
  AlojamentoLocal::RegistrationMetrics.validate!(metrics)
  %i[run_id source_files methodology_version source_dates].each do |key|
    raise "Metric provenance differs: #{key}" unless metrics.fetch(key) == metadata.fetch(key)
  end
  %i[run_id methodology_version source_dates].each do |key|
    raise "Summary provenance differs: #{key}" unless summary.fetch(key) == metadata.fetch(key)
  end
  city = metrics.fetch(:rows).first
  raise "City announcement count differs" unless city.fetch(:announcements) == summary.fetch(:listings)
  raise "City official entry count differs" unless city.fetch(:official_entries) == summary.fetch(:official_registers_lisbon)
rescue => error
  abort "Cannot regenerate report: missing or invalid snapshot registration metrics (#{error.message}). Existing report unchanged."
end
groups = CSV.read(File.join(run_dir, "licence_groups.csv"), headers: true).map { |row| row.to_h.transform_keys(&:to_sym) }
freguesias = CSV.read(File.join(run_dir, "listings.csv"), headers: true).map { |row| row.to_h.transform_keys(&:to_sym) }

report = AlojamentoLocal::Report.complete_html(metadata, summary, groups, freguesias, metrics)
File.write(File.join(run_dir, "report.html"), report)
puts "Regenerated #{File.join(run_dir, "report.html")}"
