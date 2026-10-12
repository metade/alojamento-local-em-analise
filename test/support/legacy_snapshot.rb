require "csv"
require "json"

# Only for compatibility tests. Production no longer writes split-file exports.
module LegacySnapshot
  def self.write(path, snapshot, methodology_version: nil)
    data = JSON.parse(JSON.generate(snapshot.to_h))
    data.fetch("metadata")["output_schema_version"] = "4.0.0"
    if methodology_version
      %w[metadata summary registration_metrics].each { |field| data.fetch(field)["methodology_version"] = methodology_version }
    end
    %w[metadata summary registration_metrics].each do |field|
      File.write(File.join(path, "#{field}.json"), JSON.pretty_generate(data.fetch(field)) + "\n")
    end
    AlojamentoLocal::PublicSnapshot::TABLES.each do |filename, field|
      headers = AlojamentoLocal::PUBLIC_CSV_SCHEMAS.fetch(filename)
      rows = snapshot.legacy_rows(field)
      CSV.open(File.join(path, filename), "w") do |csv|
        csv << headers
        rows.each { |row| csv << headers.map { |key| row.fetch(key) } }
      end
    end
  end
end
