require "json"
require "json_schemer"

module AlojamentoLocal
  # The current snapshot document is the interface shared by analysis and consumers.
  module PublicSnapshot
    FILE = "snapshot.json"
    SCHEMA = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../../schema/snapshot.schema.json", __dir__))))

    def self.load(path, expected_run_id: File.basename(path))
      data = JSON.parse(File.read(File.join(path, FILE)))
      validate!(data, expected_run_id: expected_run_id)
    end

    def self.validate!(data, expected_run_id:)
      error = SCHEMA.validate(data).first
      raise "Invalid snapshot schema: #{error.fetch('error')}" if error
      Validator.new.validate!(data, expected_run_id: expected_run_id)
    end
  end
end
