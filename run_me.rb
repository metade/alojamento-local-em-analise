#!/usr/bin/env ruby
require_relative "lib/alojamento_local"

mode = AlojamentoLocal::CLI.mode!(ARGV)
force = AlojamentoLocal::CLI.force?(ARGV)
reuse_existing = AlojamentoLocal::CLI.reuse_existing?(ARGV)
abort "--reuse-existing is only supported in public mode" if reuse_existing && mode != "public"
airbnb_path, official_path = AlojamentoLocal::Data.prepare!
if reuse_existing
  existing = AlojamentoLocal::Analysis.existing_public_run(airbnb_path: airbnb_path, official_path: official_path)
  if existing
    puts "Run #{existing[:run_id]} já existe; a análise pública será reutilizada sem reescrever o snapshot."
    exit 0
  end
end
result = AlojamentoLocal::Analysis.run(
  airbnb_path: airbnb_path,
  official_path: official_path,
  generate_pdf: ENV["GENERATE_PDF"] == "1",
  mode: mode,
  force: force
)

puts "Run #{result[:run_id]} criado em #{result[:path]}"
puts JSON.pretty_generate(result[:summary])
