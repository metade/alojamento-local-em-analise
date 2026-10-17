require "json"
require "json_schemer"

module AlojamentoLocal
  # Cleaned snapshot shared by presentation and publication audits.
  class CandidateDataset
    DEFAULT_PATH = File.expand_path("../../data/snapshots/candidate", __dir__)
    FILE = "snapshot.json"
    SCHEMA = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../../schema/candidate_snapshot.schema.json", __dir__))))

    attr_reader :path, :document

    def initialize(path = DEFAULT_PATH, document: nil)
      @path = File.expand_path(path)
      @document = document || JSON.parse(File.read(File.join(@path, FILE)))
      error = SCHEMA.validate(@document).first
      raise ArgumentError, "Invalid candidate snapshot schema at #{error.fetch("data_pointer")}: #{error.fetch("error")}" if error
      validate_accounting!
    end

    def self.validate!(document)
      new(document: document)
      document
    end

    def rnal
      document.fetch("rnal")
    end

    def listings
      document.fetch("listings")
    end

    def candidates
      document.fetch("candidates")
    end

    private

    def check(condition, message)
      raise ArgumentError, "Invalid candidate snapshot: #{message}" unless condition
    end

    def validate_accounting!
      [rnal, listings].each do |population|
        parishes = population.fetch("parishes").map { |row| row.fetch("freguesia") }
        check(parishes.sort_by(&:to_s) == (Geography::PARISHES + [nil]).sort_by(&:to_s), "expected every parish and unknown once")
      end
      check(listings["parishes"].sum { |row| row["count"] } == listings.dig("lisbon", "count"), "original listing totals differ")
      # RNAL counts distinct numbers in each geography. A number can appear in
      # records from several parishes; local distinct counts need not be additive.
      official_counts = rnal["parishes"].map { |row| row["count"] }
      check(rnal.dig("lisbon", "count").between?(official_counts.max, official_counts.sum), "RNAL counts disagree across geographies")
      check(candidates.map { |candidate| candidate["id"] }.uniq.size == candidates.size, "duplicate candidate ID")
      candidates.each do |candidate|
        check(candidate["listing_count"] == candidate["listing_ids"].size, "listing count differs")
      end
      linked_ids = candidates.flat_map { |candidate| candidate["listing_ids"] }.uniq
      check(linked_ids.size <= listings.dig("lisbon", "count"), "candidate references exceed original listings")

    end
  end
end
