require "json"
require "json_schemer"
require "date"

module AlojamentoLocal
  # The sole public contract, shared by builders, presentation and audits.
  class CandidateDataset
    ROOT = File.expand_path("../../data/snapshots", __dir__)
    FILE = "snapshot.json"
    SCHEMA = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../../schema/candidate_snapshot.schema.json", __dir__))))

    attr_reader :path, :document

    def self.default_path(root: ROOT)
      path = Dir.glob(File.join(root, "????-??-??__????-??-??")).select { |item| File.directory?(item) }.max
      raise "No dated candidate snapshot in #{root}" unless path
      path
    end

    def initialize(path = nil, document: nil)
      @path = File.expand_path(path || (document ? ROOT : self.class.default_path))
      @document = document || JSON.parse(File.read(File.join(@path, FILE)))
      error = SCHEMA.validate(@document).first
      raise ArgumentError, "Invalid candidate snapshot schema at #{error.fetch("data_pointer")}: #{error.fetch("error")}" if error
      validate_accounting!
      if File.basename(@path).match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}__[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
        dates = File.basename(@path).split("__")
        dates.each { |date| Date.iso8601(date) }
        check(dates.first == @document.dig("source_dates", "airbnb_snapshot_date"), "folder archive date differs")
      end
    end

    def self.validate!(document)
      new(document: document)
      document
    end

    def download_path
      "/snapshots/#{File.basename(path)}/#{FILE}"
    end

    def rnal = document.fetch("rnal")

    def listings = document.fetch("listings")

    def candidates = document.fetch("candidates")

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
      counts = rnal["parishes"].map { |row| row["count"] }
      check(rnal.dig("lisbon", "count").between?(counts.max, counts.sum), "RNAL counts disagree across geographies")
      check(candidates.map { |c| c["id"] }.uniq.size == candidates.size, "duplicate candidate ID")
      contributions = {}
      raw_values = {}
      candidates.each do |candidate|
        ids = candidate.fetch("listing_ids")
        number = candidate["al_number"]
        check(candidate["listing_count"] == ids.size, "listing count differs")
        check(candidate["raw_licences"].keys.sort == ids.sort, "raw licence mapping differs")
        check(number || ids.size == 1, "unnumbered contributions must be singletons")
        check(candidate["grouping_reason"] == ((ids.size > 1) ? "scored_merge" : "single_listing"), "grouping reason differs")
        ids.each do |id|
          key = [number, id]
          check(!contributions.key?(key), "duplicate listing–number contribution")
          contributions[key] = candidate["id"]
          raw = candidate["raw_licences"][id]
          check(!raw_values.key?(id) || raw_values[id] == raw, "conflicting raw licence values")
          raw_values[id] = raw
        end
      end
      check(raw_values.size == listings.dig("lisbon", "count"), "candidate listing coverage differs")
      by_listing = contributions.keys.group_by(&:last)
      by_id = candidates.to_h { |candidate| [candidate["id"], candidate] }
      raw_values.each do |id, raw|
        declaration = Analysis::Declaration.new(raw)
        expected = declaration.numbers.empty? ? [nil] : declaration.numbers
        actual = by_listing.fetch(id).map(&:first)
        check(expected.to_set == actual.to_set, "listing–number coverage differs for #{id}")
        if expected == [nil]
          candidate = by_id.fetch(contributions[[nil, id]])
          check(candidate["registration_status"] == declaration.status, "unnumbered status differs")
        end
      end
      assessments = {}
      document.fetch("grouping_assessments").each do |pair|
        ids = pair["listing_ids"].sort
        number = pair["al_number"]
        key = [number, *ids]
        check(!assessments.key?(key), "duplicate pair assessment")
        groups = ids.map { |id| contributions[[number, id]] }
        check(groups.none?(&:nil?), "invalid pair contributions")
        merged = groups.uniq.size == 1
        check(merged == (pair["outcome"] == "merge"), "assessment disagrees with final groups")
        check(!merged || pair["score"] >= 7, "merged pair below threshold")
        assessments[key] = pair
      end
      contributions.keys.group_by(&:first).each do |number, keys|
        next unless number
        keys.map(&:last).sort.combination(2) do |a, b|
          check(assessments.key?([number, a, b]), "missing pair assessment")
        end
      end
    end
  end
end
