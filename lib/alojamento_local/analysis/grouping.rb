require "set" # standard:disable Lint/RedundantRequireStatement
require "cgi"
require "rdoc"
require "rdoc/markdown/entities"

module AlojamentoLocal
  module Analysis
    # Scores describe evidence, not probabilities. RNAL only resolves supported separations.
    class Grouping
      attr_reader :assessments, :groups
      POINTS = {"distance_le_500m" => 1, "same_host" => 1, "similar_title" => 2,
                "strong_description" => 3, "same_apartment_reference" => 3, "same_al_number" => 2,
                "same_host_room_group" => 1}.freeze
      OFFSETS = [-1, 0, 1].repeated_permutation(3).to_a.freeze

      def initialize(entries, official_records: {})
        @official_records = official_records
        @entries = entries.sort_by { |entry| entry.raw.fetch("id") }
        @prepared = @entries.to_h { |entry| [entry.raw.fetch("id"), prepare(entry)] }
        @assessments = []
        discover do |a, b, distance|
          pair = assess(a, b, distance)
          # Nearby unrelated adverts are evaluated but need no public review record.
          @assessments << pair if retain_assessment?(pair)
        end
        @assessments.sort_by! { |pair| pair["listing_ids"] }
        @pairs = assessments.to_h { |pair| [pair.fetch("listing_ids"), pair] }
        complete_link!
      end

      def self.distance(a, b)
        return nil unless a && b
        Haversine.distance(a[0], a[1], b[0], b[1]).to_km
      end

      def self.medoid(entries)
        located = entries.select(&:coordinates)
        located.min_by do |entry|
          [located.sum { |other| distance(entry.coordinates, other.coordinates) }, entry.raw.fetch("id")]
        end&.coordinates
      end

      private

      # Prepare each listing once before searching for pairs.
      def normalize(value)
        text = value.to_s.gsub(/<\s*(?:br\b[^>]*|\/?(?:p|div|li)\b[^>]*)>/i, "\n").gsub(/<[^>]*>/, " ").gsub(/&(?:[A-Za-z][A-Za-z0-9]+|\#[0-9]+|\#[xX][0-9a-fA-F]+);/) do |entity|
          codepoints = RDoc::Markdown::HTML_ENTITIES[entity[1...-1]]
          codepoints ? codepoints.pack("U*") : CGI.unescapeHTML(entity)
        end
        text.unicode_normalize(:nfkc)
      end

      def reference(text, labels)
        values = Array(text).flat_map do |field|
          field.to_enum(:scan, /\b(?:#{labels})(?![\p{L}\p{N}])[[:blank:]]*(?:no\.?[[:blank:]]*|n[º°.][[:blank:]]*|#[[:blank:]]*)?([\p{L}\p{N}]+)\b/i).filter_map do
            match = Regexp.last_match
            value = match[1]
            next unless value.match?(/\A(?:[a-z0-9]*[0-9][a-z0-9]*|[a-z])\z/i)
            next if match.post_match.match?(/\A[\/\\’']/)
            next if match.post_match.match?(/\A(?:[-_][\p{L}\p{N}]|[.,]\s*[0-9]|\s*&\s*[\p{L}\p{N}])/)
            next if value.match?(/\A(?:t[0-9]+|[0-9]+(?:br|bdrms?|bedrooms?|beds?))\z/i)
            next if value.match?(/\A[0-9]+(?:st|nd|rd|th)\z/i) && match.post_match.match?(/\A\s+floor\b/i)
            next if match.post_match.match?(/\A\s*[-–]\s*[0-9]+/)
            # Counts and articles are ambiguous, not explicit unit identifiers.
            next if match.post_match.match?(/\A\s*(?:bedrooms?|beds?|bathrooms?|br|bdrms?|rooms|quartos|camas|guests?|pessoas?|floors?|pisos?|andares?)\b(?!\s+[0-9]+\b)/i)
            next if %w[a o w].include?(value) && match.post_match.match?(/\A\s+\p{L}/)
            value.downcase
          end
        end.uniq
        values.first if values.size == 1
      end

      def numeric(value)
        number = Float(value, exception: false)
        number if number&.finite? && number >= 0
      end

      def prepare(entry)
        text = %w[name description].map { |key| normalize(entry.raw[key]) }
        category = {"Entire home/apt" => "entire", "Private room" => "private", "Shared room" => "shared", "Hotel room" => "hotel"}[entry.raw["room_type"]]
        property = normalize(entry.raw["property_type"]).downcase.strip
        property = property.sub(/\Aentire\s+/, "")
        property = "apartment" if %w[apartment flat].include?(property) || property == "rental unit"
        {tokens: text.map { |value| value.downcase.scan(/[\p{L}\p{N}]+/).to_set },
         apartment: reference(text, "apartment|flat|apartamento|apt\\.?|unidade"),
         room: reference(text, "room|quarto|bed|cama"),
         category: category, property: property.empty? ? nil : property,
         single_declaration: entry.declaration.numbers.one? && !entry.declaration.partial?,
         attributes: %w[bedrooms beds bathrooms accommodates].to_h { |key| [key, numeric(entry.raw[key])] },
         host: entry.raw["host_id"].to_s.strip, numbers: entry.declaration.numbers,
         registered_apartment: locally_registered_apartment?(entry, category, property)}
      end

      def locally_registered_apartment?(entry, category, property)
        declaration = entry.declaration
        return false unless category == "entire" && property == "apartment" && declaration.numbers.one? && !declaration.partial?
        record = @official_records[declaration.numbers.first]
        return false unless record && Geography.key(record["type"]) == "apartamento" && record["municipality"] == "Lisboa"
        distance = self.class.distance(entry.coordinates, record["coordinates"])
        distance && distance <= 0.5
      end

      # Pair discovery uses spatial cells, shared numbers and unit references.
      # Cartesian cells on the earth's surface avoid longitude/polar boundary assumptions.
      def cell(entry)
        return unless entry.coordinates
        lat, lon = entry.coordinates.map { |value| value * Math::PI / 180 }
        [Math.cos(lat) * Math.cos(lon), Math.cos(lat) * Math.sin(lon), Math.sin(lat)].map { |value| (value * 6371 / 0.5).floor }
      end

      def discover
        grid = Hash.new { |h, k| h[k] = [] }
        numbers = Hash.new { |h, k| h[k] = [] }
        units = Hash.new { |h, k| h[k] = [] }
        @entries.each do |entry|
          data = @prepared.fetch(entry.raw["id"])
          nearby = []
          position = cell(entry)
          if position
            OFFSETS.each do |offset|
              nearby.concat(grid.fetch(position.zip(offset).map { |a, b| a + b }, []))
            end
          end
          others = data[:numbers].flat_map { |number| numbers[number] }
          others.concat(units[data[:apartment]]) if data[:apartment]
          forced = others.map { |other| other.raw["id"] }.to_set
          (nearby + others).uniq { |other| other.raw["id"] }.sort_by { |other| other.raw["id"] }.each do |other|
            distance = self.class.distance(other.coordinates, entry.coordinates)
            yield other, entry, distance if forced.include?(other.raw["id"]) || (distance && distance <= 0.5)
          end
          grid[position] << entry if position
          data[:numbers].each { |number| numbers[number] << entry }
          units[data[:apartment]] << entry if data[:apartment]
        end
      end

      def similar?(a, b, minimum:, threshold:, shared: 0)
        return false if a.size < minimum || b.size < minimum
        intersection = (a & b).size
        intersection >= shared && intersection.to_f / (a.size + b.size - intersection) >= threshold
      end

      # Pair assessment: collect evidence, score it, decide, then label the relationship.
      def assess(a, b, distance)
        first, second = [a, b].map { |entry| @prepared.fetch(entry.raw["id"]) }
        reasons = evidence_for(first, second, distance)
        score = reasons.sum { |reason| POINTS.fetch(reason, 0) }
        outcome, decision_reason = decide(first, second, reasons, score)
        reasons << decision_reason
        {"listing_ids" => [a.raw["id"], b.raw["id"]], "score" => score,
         "outcome" => outcome, "relationship" => relationship_for(first, second, reasons, outcome), "reasons" => reasons}
      end

      def evidence_for(first, second, distance)
        distance_reason = if distance.nil?
          "missing_coordinates"
        elsif distance <= 0.5
          "distance_le_500m"
        else
          "distance_over_500m"
        end
        reasons = [distance_reason]
        reasons << "same_host" if !first[:host].empty? && first[:host] == second[:host]
        reasons << "similar_title" if similar?(first[:tokens][0], second[:tokens][0], minimum: 3, shared: 3, threshold: 0.5)
        reasons << "strong_description" if similar?(first[:tokens][1], second[:tokens][1], minimum: 30, threshold: 0.8)
        if first[:apartment] && second[:apartment]
          reasons << ((first[:apartment] == second[:apartment]) ? "same_apartment_reference" : "different_apartment_reference")
        end
        reasons << "same_room_reference" if first[:room] && first[:room] == second[:room]
        reasons << "different_room_references" if first[:room] && second[:room] && first[:room] != second[:room]
        reasons << "same_al_number" if (first[:numbers] & second[:numbers]).any?
        reasons << "conflicting_al_numbers" if first[:numbers].any? && second[:numbers].any? && first[:numbers] != second[:numbers]
        reasons << "multiple_al_numbers" if [first, second].any? { |data| data[:numbers].size > 1 }
        categories = [first[:category], second[:category]]
        reasons << "room_category_ambiguity" if categories.any?(&:nil?)
        reasons << "different_room_categories" if categories.none?(&:nil?) && categories.uniq.size > 1
        reasons.concat(apartment_contradictions(first, second))
        reasons << "same_host_room_group" if same_host_room_group?(first, second, reasons)
        reasons
      end

      def same_host_room_group?(first, second, reasons)
        (%w[distance_le_500m same_host same_al_number strong_description] - reasons).empty? &&
          !contradictory_evidence?(reasons) &&
          [first, second].any? { |data| data[:category] == "private" } &&
          [first, second].all? do |data|
            data[:single_declaration] && (data[:category] == "private" || (data[:category] == "entire" && data[:property] == "apartment"))
          end
      end

      def apartment_contradictions(first, second)
        return [] unless [first[:category], second[:category]] == %w[entire entire]
        reasons = %w[bedrooms beds bathrooms accommodates].filter_map do |key|
          values = [first, second].map { |data| data[:attributes][key] }
          "different_apartment_#{key}" if values.none?(&:nil?) && values.uniq.size > 1
        end
        properties = [first[:property], second[:property]]
        reasons << "different_apartment_property" if properties.none?(&:nil?) && properties.uniq.size > 1
        reasons
      end

      def decide(first, second, reasons, score)
        return ["merge", "merge_threshold"] if merge_eligible?(reasons, score)
        return ["separate", "insufficient_identity"] unless plausible_relationship?(reasons)
        return ["separate", "distinct_registered_apartments"] if registered_apartments_distinct?(first, second, reasons)
        return ["separate", "distinct_apartment_attributes"] if apartment_attributes_distinct?(reasons)
        ["review", "review_score"]
      end

      def merge_eligible?(reasons, score)
        score >= 8 && reasons.include?("distance_le_500m") &&
          !contradictory_evidence?(reasons) && identity_evidence?(reasons) &&
          (!reasons.include?("different_room_categories") || (reasons & %w[same_apartment_reference same_host_room_group]).any?)
      end

      def identity_evidence?(reasons)
        explicit_unit_with_text = reasons.include?("same_apartment_reference") && (reasons & %w[similar_title strong_description]).any?
        shared_number_with_text = (%w[same_al_number similar_title strong_description] - reasons).empty?
        explicit_unit_with_text || shared_number_with_text || reasons.include?("same_host_room_group")
      end

      def contradictory_evidence?(reasons)
        reasons.any? { |reason| reason.start_with?("different_apartment_") } ||
          (reasons & %w[conflicting_al_numbers multiple_al_numbers]).any?
      end

      def plausible_relationship?(reasons)
        (reasons & %w[same_apartment_reference same_al_number]).any? ||
          (%w[similar_title strong_description] - reasons).empty? ||
          (reasons.include?("conflicting_al_numbers") && (reasons & %w[similar_title strong_description]).any?)
      end

      def registered_apartments_distinct?(first, second, reasons)
        reasons.include?("conflicting_al_numbers") && !reasons.include?("same_apartment_reference") &&
          reasons.include?("distance_le_500m") && first[:registered_apartment] && second[:registered_apartment]
      end

      def apartment_attributes_distinct?(reasons)
        (%w[same_al_number different_apartment_bedrooms different_apartment_beds different_apartment_accommodates] - reasons).empty? &&
          (reasons & %w[same_apartment_reference conflicting_al_numbers multiple_al_numbers]).empty?
      end

      # Merging accommodation does not necessarily establish duplicate adverts.
      def relationship_for(first, second, reasons, outcome)
        categories = [first[:category], second[:category]]
        return "separate_apartments" if (reasons & %w[distinct_registered_apartments distinct_apartment_attributes]).any?
        if categories.none?(&:nil?) && categories.include?("entire") && categories.uniq.size > 1
          return "apartment_and_rooms"
        end
        return "separate_rooms" if (reasons & %w[different_room_references different_room_categories]).any?
        return "separate_rooms" if reasons.include?("same_host_room_group") && !reasons.include?("same_room_reference")
        if outcome == "merge" && categories.none?(&:nil?) && (categories == %w[entire entire] || reasons.include?("same_room_reference"))
          return "duplicate_adverts"
        end
        "undetermined"
      end

      def retain_assessment?(pair)
        pair["outcome"] != "separate" ||
          (pair["reasons"] & %w[same_al_number same_apartment_reference different_apartment_reference distinct_registered_apartments]).any?
      end

      # Every cross-pair must qualify; prefer the highest minimum score, then listing IDs.
      def complete_link!
        memberships = @entries.to_h { |entry| [entry.raw["id"], [entry]] }
        edges = assessments.select { |pair| pair["outcome"] == "merge" }
        loop do
          seen = Set.new
          eligible = edges.filter_map do |edge|
            a, b = edge["listing_ids"].map { |id| memberships.fetch(id) }
            next if a.equal?(b)
            ids = (a + b).map { |entry| entry.raw["id"] }.sort
            next unless seen.add?(ids)
            pairs = a.product(b).map { |left, right| @pairs[[left.raw["id"], right.raw["id"]].sort] }
            next unless pairs.all? { |pair| pair && pair["outcome"] == "merge" }
            [a, b, pairs.map { |pair| pair["score"] }.min, ids]
          end
          best = eligible.min_by { |_, _, score, ids| [-score, ids] }
          break unless best
          a, b = best
          group = (a + b).sort_by { |entry| entry.raw["id"] }
          group.each { |entry| memberships[entry.raw["id"]] = group }
        end
        edges.each do |pair|
          unless memberships[pair["listing_ids"][0]].equal?(memberships[pair["listing_ids"][1]])
            pair["outcome"] = "review"
            pair["reasons"] << "complete_link_conflict"
          end
        end
        @groups = memberships.values.uniq.sort_by { |group| group.map { |entry| entry.raw["id"] } }
      end
    end
  end
end
