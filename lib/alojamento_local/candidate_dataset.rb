require "set" # standard:disable Lint/RedundantRequireStatement
require "json"
require "json_schemer"
require "date"
require "zlib"
require "stringio"
require "digest"
require "fileutils"

module AlojamentoLocal
  # The sole public contract, shared by builders, presentation and audits.
  class CandidateDataset
    ROOT = File.expand_path("../../data/snapshots", __dir__)
    FILES = %w[summary.json candidates.json.gz].freeze
    SCHEMAS = %w[summary details].map do |name|
      JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../../schema/candidate_#{name}.schema.json", __dir__))))
    end.freeze
    DISTANCE_RANGES = %w[up_to_500_m 500_m_1_km 1_2_km 2_5_km over_5_km unresolved].freeze

    attr_reader :path, :summary_document, :details_document

    def self.default_path(root: ROOT)
      with_lock(File.join(root, ".selection")) do
        path = Dir.glob(File.join(root, "????-??-??__????-??-??")).select { |item| File.directory?(item) }.max
        raise "No dated candidate snapshot in #{root}" unless path
        path
      end
    end

    def self.with_lock(path, mode = File::LOCK_SH)
      File.open(File.dirname(File.expand_path(path)), "r") do |lock|
        lock.flock(mode)
        yield
      ensure
        lock&.flock(File::LOCK_UN)
      end
    end

    def initialize(path = nil, summary_document: nil, details_document: nil)
      raise ArgumentError, "Supply both summary and details" if !!summary_document != !!details_document
      @path = File.expand_path(path || (summary_document ? ROOT : self.class.default_path))
      if summary_document
        @summary_document, @details_document = summary_document, details_document
      else
        self.class.with_lock(@path) do
          bytes = FILES.map { |file| File.binread(File.join(@path, file)) }
          @source_hashes = bytes.map { |value| Digest::SHA256.hexdigest(value) }
          @summary_document = JSON.parse(bytes.first)
          io = StringIO.new(bytes.last)
          gzip = Zlib::GzipReader.new(io)
          @details_document = JSON.parse(gzip.read)
          raise ArgumentError, "Trailing gzip data" if gzip.unused || io.pos < bytes.last.bytesize
          gzip.close
        end
      end
      [@summary_document, @details_document].zip(SCHEMAS).each do |document, schema|
        error = schema.validate(document).first
        raise ArgumentError, "Invalid candidate snapshot schema at #{error.fetch("data_pointer")}: #{error.fetch("error")}" if error
      end
      validate_accounting!
      if File.basename(@path).match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}__[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
        dates = File.basename(@path).split("__")
        dates.each { |date| Date.iso8601(date) }
        check(dates.first == @summary_document.dig("source_dates", "airbnb_snapshot_date"), "folder archive date differs")
      end
    end

    def download_paths
      FILES.map { |file| "/snapshots/#{File.basename(path)}/#{file}" }
    end

    def copy_downloads(destination)
      self.class.with_lock(path) do
        bytes = FILES.map { |file| File.binread(File.join(path, file)) }
        check(@source_hashes == bytes.map { |value| Digest::SHA256.hexdigest(value) }, "source files changed during build")
        FileUtils.mkdir_p(destination)
        FILES.zip(bytes).each { |file, value| File.binwrite(File.join(destination, file), value) }
      end
    end

    def write_files(destination)
      FileUtils.mkdir_p(destination)
      bytes = [JSON.pretty_generate(summary_document) + "\n", self.class.compress(details_document)]
      FILES.zip(bytes).each do |name, value|
        File.open(File.join(destination, name), "wb") do |file|
          file.write(value)
          file.flush
          file.fsync
        end
      end
    end

    def self.compress(document)
      io = StringIO.new("".b)
      gzip = Zlib::GzipWriter.new(io, 9)
      gzip.mtime = 0
      gzip.write(JSON.generate(document).encode(Encoding::UTF_8) + "\n")
      gzip.close
      io.string
    end

    def candidates = details_document.fetch("candidates")

    def grouping_assessments = details_document.fetch("grouping_assessments")

    def summary
      scope = summary_document.fetch("lisbon")
      {listings: scope.fetch("listings_count"), candidates: scope.fetch("candidates_count"),
       distinct_al_numbers: scope.fetch("distinct_al_numbers_count"), rnal: scope.fetch("official_count")}
    end

    def self.candidate_aggregates(candidates)
      ids = ->(rows) { rows.flat_map { |c| c.fetch("listing_ids") }.uniq }
      scope = ->(rows) {
        numbers = rows.filter_map { |c| c["al_number"] }
        {"candidates_count" => rows.size, "numbered_candidates_count" => numbers.size, "distinct_al_numbers_count" => numbers.uniq.size,
         "exempt_candidates_count" => rows.count { |c| c["registration_status"] == "exempt" },
         "empty_licence_candidates_count" => rows.count { |c| c["registration_status"] == "absent" },
         "unrecognised_licence_candidates_count" => rows.count { |c| c["registration_status"] == "unrecognised" },
         "mixed_licence_candidates_count" => rows.count { |c| c["registration_status"] == "mixed" }}
      }
      declarations = candidates.flat_map { |c| c.fetch("raw_licences").to_a }.uniq.to_h
      empty = declarations.select { |_, raw| Analysis::Declaration.new(raw).status == "absent" }.keys
      unrecognised = declarations.select { |_, raw| Analysis::Declaration.new(raw).status == "unrecognised" }.keys
      repeated = candidates.select { |c| c["al_number"] }.group_by { |c| c["al_number"] }.values.select { |group| group.size > 1 }
      distances = Array.new(6, 0)
      repeated.each do |group|
        values = group.map { |c| c.dig("official_match", "distance_km") }
        index = values.any?(&:nil?) ? 5 : [0.5, 1, 2, 5, Float::INFINITY].index { |upper| values.max <= upper }
        distances[index] += 1
      end
      regions_by_listing = Hash.new { |hash, id| hash[id] = [] }
      candidates.each do |candidate|
        record = candidate["official_match"]
        next unless record
        municipality = Geography.municipality(record["municipality"])
        next unless municipality && municipality != "Lisboa"
        region = record["district"]&.strip
        region = nil if region.to_s.empty?
        candidate["listing_ids"].each { |id| regions_by_listing[id] << region }
      end
      regions = Hash.new(0)
      regions_by_listing.each_value { |values| regions[(values.uniq.size == 1) ? values.first : nil] += 1 }
      {"lisbon" => scope.call(candidates),
       "parishes" => (Geography::PARISHES + [nil]).map { |parish| {"freguesia" => parish}.merge(scope.call(candidates.select { |c| c["freguesia"] == parish })) },
       "signals" => {"empty_licence_listings" => empty.size, "unrecognised_licence_listings" => unrecognised.size,
                     "unidentified_licence_listings" => (empty | unrecognised).size, "repeated_listings" => ids.call(repeated.flatten).size,
                     "outside_listings" => regions_by_listing.size},
       "repeated_number_distances" => DISTANCE_RANGES.zip(distances).map { |range, count| {"range" => range, "count" => count} },
       "outside_regions" => regions.sort_by { |name, count| [name.nil? ? 1 : 0, -count, name.to_s] }.map { |name, count| {"district" => name, "count" => count} }}
    end

    private

    def check(condition, message)
      raise ArgumentError, "Invalid candidate snapshot: #{message}" unless condition
    end

    def validate_accounting!
      parishes = summary_document.fetch("parishes")
      check(parishes.map { |row| row["freguesia"] } == Geography::PARISHES + [nil], "expected every parish and unknown in order")
      city = summary_document.fetch("lisbon")
      check(parishes.sum { |row| row["listings_count"] } == city["listings_count"], "original listing totals differ")
      counts = parishes.map { |row| row["official_count"] }
      check(city["official_count"].between?(counts.max, counts.sum), "RNAL counts disagree across geographies")
      ([city] + parishes).each do |scope|
        check(scope["matched_al_numbers_count"] <= [scope["official_count"], scope["distinct_al_numbers_count"]].min, "overlap exceeds a source population")
        check(scope["matched_al_numbers_count"] <= city["matched_al_numbers_count"], "parish overlap exceeds city overlap")
        rows = scope.equal?(city) ? candidates : candidates.select { |candidate| candidate["freguesia"] == scope["freguesia"] }
        found = rows.select { |candidate| candidate["registration_status"] == "found" }.map { |candidate| candidate["al_number"] }.uniq.size
        check(scope["matched_al_numbers_count"] <= found, "overlap exceeds nationally found numbers")
      end
      aggregates = self.class.candidate_aggregates(candidates)
      aggregates.each do |key, expected|
        actual = summary_document.fetch(key)
        if key == "lisbon"
          actual = actual.slice(*expected.keys)
        elsif key == "parishes"
          actual = actual.map { |row| row.slice(*expected.first.keys) }
        end
        check(actual == expected, "summary/detail disagreement: #{key}")
      end
      check(candidates.map { |c| c["id"] }.uniq.size == candidates.size, "duplicate candidate ID")
      contributions = {}
      raw_values = {}
      candidates.each do |candidate|
        ids = candidate.fetch("listing_ids")
        number = candidate["al_number"]
        check(candidate["listing_count"] == ids.size, "listing count differs")
        check(candidate["raw_licences"].keys.sort == ids.sort, "raw licence mapping differs")
        declared = candidate["raw_licences"].values.map { |raw| Analysis::Declaration.new(raw) }
        numbers = declared.flat_map(&:numbers).uniq
        check(number ? numbers.include?(number) : numbers.empty?, "candidate number lacks declaration")
        if ids.size > 1
          check(numbers.size <= 1, "merged group has multiple declared numbers")
          check(declared.none? { |declaration| declaration.numbers.size > 1 }, "multiple-number listing merged")
        end
        unless number
          statuses = declared.map(&:status).uniq
          check(candidate["registration_status"] == ((statuses.size == 1) ? statuses.first : "mixed"), "unnumbered status differs")
        end
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
      check(raw_values.size == city["listings_count"], "candidate listing coverage differs")
      by_listing = contributions.keys.group_by(&:last)
      raw_values.each do |id, raw|
        declaration = Analysis::Declaration.new(raw)
        expected = declaration.numbers.empty? ? [nil] : declaration.numbers
        actual = by_listing.fetch(id).map(&:first)
        if expected == [nil]
          check(actual.size == 1, "unnumbered listing repeated")
        else
          check(expected.to_set == actual.to_set, "listing–number coverage differs for #{id}")
        end
      end
      assessments = {}
      memberships = Hash.new { |hash, id| hash[id] = [] }
      candidates.each { |candidate| candidate["listing_ids"].each { |id| memberships[id] << candidate["id"] } }
      candidates_by_id = candidates.to_h { |candidate| [candidate["id"], candidate] }
      grouping_assessments.each do |pair|
        ids = pair["listing_ids"].sort
        validate_pair_details!(pair)
        check(!assessments.key?(ids), "duplicate pair assessment")
        check(ids.all? { |id| memberships.key?(id) }, "invalid pair contributions")
        reasons = pair["reasons"]
        check(pair["score"] == reasons.sum { |reason| Analysis::Grouping::POINTS.fetch(reason, 0) }, "pair score differs")
        if reasons.include?("same_al_number")
          numbers = ids.map { |id| Analysis::Declaration.new(raw_values.fetch(id)).numbers }
          check((numbers[0] & numbers[1]).any?, "pair claims an undeclared shared number")
        end
        room_identity = reasons.include?("same_host_room_group")
        if room_identity
          check((%w[distance_le_500m same_host same_al_number strong_description] - reasons).empty?, "host room group lacks supporting evidence")
          check((reasons & %w[conflicting_al_numbers multiple_al_numbers room_category_ambiguity]).empty? && reasons.none? { |reason| reason.start_with?("different_apartment_") }, "host room group has contradictory evidence")
          declarations = ids.map { |id| Analysis::Declaration.new(raw_values.fetch(id)) }
          check(declarations.all? { |declaration| declaration.numbers.one? && !declaration.partial? }, "host room group requires complete single declarations")
          relationship = if reasons.include?("different_room_categories")
            "apartment_and_rooms"
          elsif reasons.include?("same_room_reference")
            "duplicate_adverts"
          else
            "separate_rooms"
          end
          check(pair["relationship"] == relationship, "host room group relationship differs")
        end
        merged = (memberships[ids[0]] & memberships[ids[1]]).any?
        check(merged == (pair["outcome"] == "merge"), "assessment disagrees with final groups")
        registered_separation = reasons.include?("distinct_registered_apartments")
        attribute_separation = reasons.include?("distinct_apartment_attributes")
        check((registered_separation || attribute_separation) == (pair["relationship"] == "separate_apartments"), "apartment separation relationship differs")
        if attribute_separation
          check(pair["outcome"] == "separate", "distinct apartments must remain separate")
          beds = pair["attributes"]["beds"]
          capacity = pair["attributes"]["accommodates"]
          coherent_changes = (beds + capacity).none?(&:nil?) && (beds[0] - beds[1]) * (capacity[0] - capacity[1]) > 0
          check((%w[same_al_number different_apartment_beds different_apartment_accommodates] - reasons).empty? &&
            (reasons.include?("different_apartment_bedrooms") || (reasons.include?("different_apartment_text") && coherent_changes)), "apartment separation lacks attribute evidence")
          check((reasons & %w[same_apartment_reference conflicting_al_numbers multiple_al_numbers room_category_ambiguity different_room_categories]).empty?, "apartment separation has conflicting identity evidence")
        end
        if registered_separation
          check(pair["outcome"] == "separate", "registered apartments must remain separate")
          check((%w[distance_le_500m conflicting_al_numbers] - reasons).empty?, "registered separation lacks evidence")
          check((reasons & %w[same_apartment_reference multiple_al_numbers room_category_ambiguity different_room_categories]).empty?, "registered separation has conflicting unit evidence")
          declarations = ids.map { |id| Analysis::Declaration.new(raw_values.fetch(id)) }
          check(declarations.all? { |declaration| declaration.numbers.one? && !declaration.partial? } && declarations.map(&:numbers).uniq.size == 2, "registered separation requires distinct single declarations")
          ids.each do |id|
            memberships.fetch(id).each do |candidate_id|
              candidate = candidates_by_id.fetch(candidate_id)
              record = candidate["official_match"]
              check(candidate["registration_status"] == "found" && record && record["municipality"] == "Lisboa" && Geography.key(record["type"]) == "apartamento", "registered separation lacks official apartments")
            end
          end
        end
        if pair["relationship"] == "duplicate_adverts"
          check(%w[merge_threshold complete_link_conflict].include?(pair["decision_reason"]), "duplicate relationship lacks qualifying identity evidence")
          check((reasons & %w[room_category_ambiguity different_room_categories different_room_references]).empty?, "duplicate relationship has ambiguous or different rooms")
        end
        if merged || pair["relationship"] == "duplicate_adverts" || pair["decision_reason"] == "complete_link_conflict"
          check(pair["score"] >= 8, "merged pair below threshold")
          check(reasons.include?("distance_le_500m"), "merge lacks nearby coordinates")
          explicit = reasons.include?("same_apartment_reference")
          text = (reasons & %w[similar_title strong_description]).any?
          check((explicit && text) || (%w[same_al_number similar_title strong_description] - reasons).empty? || room_identity, "merge lacks identity evidence")
          check(explicit || room_identity || (pair["relationship"] != "apartment_and_rooms" && !reasons.include?("different_room_categories")), "room relationship lacks unit evidence")
          check(reasons.none? { |reason| reason.start_with?("different_apartment_") } && (reasons & %w[conflicting_al_numbers multiple_al_numbers]).empty?, "contradictory merge")
        end
        assessments[ids] = pair
      end
      candidates.each do |candidate|
        candidate["listing_ids"].sort.combination(2) do |ids|
          check(assessments[ids] && assessments[ids]["outcome"] == "merge", "missing internal merge assessment")
        end
      end
    end

    def validate_pair_details!(pair)
      reasons = pair.fetch("reasons")
      check(pair["listing_ids"] == pair["listing_ids"].sort, "pair IDs must be ordered with comparison values")
      expected = reasons.to_h { |reason| [reason, {"category" => Analysis::Grouping.evidence_category(reason), "points" => Analysis::Grouping::POINTS.fetch(reason, 0)}] }
      check(pair["evidence"] == expected, "pair evidence breakdown differs")
      {"title" => [3, 0.5, 3, "similar_title"], "description" => [30, 0.8, 0, "strong_description"]}.each do |name, (minimum, threshold, shared_minimum, reason)|
        comparison = pair.fetch("#{name}_comparison")
        counts = comparison.fetch("token_counts")
        shared = comparison.fetch("shared_tokens")
        check(shared <= counts.min, "shared tokens exceed text sizes")
        similarity = counts.include?(0) ? nil : shared.fdiv(counts.sum - shared)
        check(comparison["similarity"] == similarity&.round(4), "text similarity differs from token counts")
        if reasons.include?(reason)
          check(counts.min >= minimum && shared >= shared_minimum && similarity && similarity >= threshold, "text evidence lacks similarity")
        end
      end
      distance = pair["distance_m"]
      check(distance && distance <= 500, "nearby distance differs") if reasons.include?("distance_le_500m")
      check(distance && distance >= 500, "distant distance differs") if reasons.include?("distance_over_500m")
      check(distance.nil?, "missing distance differs") if reasons.include?("missing_coordinates")
      pair["attributes"].each do |name, values|
        if reasons.include?("different_apartment_#{name}")
          check(pair["room_types"] == ["Entire home/apt", "Entire home/apt"] && values.none?(&:nil?) && values.uniq.size == 2, "apartment attribute evidence differs")
        end
      end
      if reasons.include?("different_apartment_text")
        check(pair["room_types"] == ["Entire home/apt", "Entire home/apt"], "different apartment text requires entire-home adverts")
        {"title" => 3, "description" => 30}.each do |name, minimum|
          comparison = pair.fetch("#{name}_comparison")
          shared = comparison.fetch("shared_tokens")
          check(comparison["token_counts"].min >= minimum && shared.fdiv(comparison["token_counts"].sum - shared) <= 0.25, "different apartment text lacks sufficient dissimilarity")
        end
      end
      decision = pair["decision_reason"]
      expected_outcome = case decision
      when "merge_threshold" then "merge"
      when "complete_link_conflict", "insufficient_merge_evidence" then "review"
      else "separate"
      end
      check(pair["outcome"] == expected_outcome, "pair decision disagrees with outcome")
      %w[distinct_registered_apartments distinct_apartment_attributes].each do |reason|
        check(reasons.include?(reason) == (decision == reason), "separation decision differs")
      end
    end
  end
end
