#!/usr/bin/env ruby
require_relative "../lib/alojamento_local"

run_dir = ARGV.fetch(0) { abort "Usage: ruby scripts/regenerate_public_report.rb RUN_DIR" }
begin
  snapshot = AlojamentoLocal::PublicSnapshot::Loader.new.load(run_dir)
  report = AlojamentoLocal::Report.complete_html(*snapshot.report_arguments)
rescue => error
  abort "Cannot regenerate report: missing or invalid public snapshot (#{error.message}). Existing report unchanged."
end
File.write(File.join(run_dir, "report.html"), report)
puts "Regenerated #{File.join(run_dir, "report.html")}"
