require "json"
require "json_schemer"

module AlojamentoLocal
  # The current snapshot document is the interface shared by analysis and consumers.
  module PublicSnapshot
    FILE = "snapshot.json"
    RUN_ID_PATTERN = /\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}\z/
    SCHEMA = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../../schema/snapshot.schema.json", __dir__))))

    def self.load_run(run_id, snapshots: "data/snapshots")
      raise ArgumentError, "Invalid public run ID: #{run_id}" unless run_id.match?(RUN_ID_PATTERN)
      path = File.join(snapshots, run_id)
      raise "Unknown public run ID: #{run_id}" unless File.file?(File.join(path, FILE))
      load(path)
    end

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
