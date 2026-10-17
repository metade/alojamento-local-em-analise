require "cgi"
require "rdoc"
require "rdoc/markdown/entities"

module AlojamentoLocal
  module Analysis
    # Scores describe evidence, not probabilities. RNAL never enters grouping.
    class Grouping
      attr_reader :assessments, :groups

      def initialize(number, entries)
        @number = number
        @entries = entries.sort_by { |entry| entry.raw.fetch("id") }
        @tokens = @entries.to_h do |entry|
          [entry.raw.fetch("id"), %w[name description].map { |key| tokens(entry.raw[key]) }]
        end
        @assessments = @entries.combination(2).map { |pair| assess(*pair) }
        @pairs = assessments.to_h { |pair| [pair.fetch("listing_ids"), pair] }
        @groups = @entries.zip
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

      def tokens(value)
        text = value.to_s.gsub(/<[^>]*>/, " ").gsub(/&(?:[A-Za-z][A-Za-z0-9]+|\#[0-9]+|\#[xX][0-9a-fA-F]+);/) do |entity|
          codepoints = RDoc::Markdown::HTML_ENTITIES[entity[1...-1]]
          codepoints ? codepoints.pack("U*") : CGI.unescapeHTML(entity)
        end
        text.unicode_normalize(:nfkc).downcase.scan(/[\p{L}\p{N}]+/).to_set
      end

      def similar?(a, b, minimum:, threshold:, shared: 0)
        a.size >= minimum && b.size >= minimum && (a & b).size >= shared &&
          !(a | b).empty? && (a & b).size.to_f / (a | b).size >= threshold
      end

      def room_category(entry)
        {"Entire home/apt" => "entire", "Private room" => "private", "Shared room" => "shared", "Hotel room" => "hotel"}[entry.raw["room_type"]]
      end

      def apartment?(entry)
        room_category(entry) == "entire" && entry.raw["property_type"].to_s.match?(/apartment|rental unit|flat|loft|condo/i)
      end

      def bedrooms(entry)
        value = Float(entry.raw["bedrooms"], exception: false)
        value if value&.finite? && value >= 0
      end

      def assess(a, b)
        reasons = []
        score = 0
        distance = self.class.distance(a.coordinates, b.coordinates)
        if distance.nil?
          reasons << "missing_coordinates"
        elsif distance <= 0.05
          score += 3
          reasons << "distance_le_50m"
        elsif distance <= 0.1
          score += 2
          reasons << "distance_le_100m"
        else
          reasons << "distance_over_100m"
        end
        host = a.raw["host_id"].to_s.strip
        if !host.empty? && host == b.raw["host_id"].to_s.strip
          score += 1
          reasons << "same_host"
        end
        first = @tokens.fetch(a.raw["id"])
        second = @tokens.fetch(b.raw["id"])
        if similar?(first[0], second[0], minimum: 3, shared: 3, threshold: 0.5)
          score += 2
          reasons << "similar_title"
        end
        if similar?(first[1], second[1], minimum: 30, threshold: 0.8)
          score += 3
          reasons << "strong_description"
        end
        categories = [room_category(a), room_category(b)]
        ambiguity = categories.any?(&:nil?)
        incompatible = !ambiguity && categories.uniq.size > 1
        contradiction = apartment?(a) && apartment?(b) && bedrooms(a) && bedrooms(b) && bedrooms(a) != bedrooms(b)
        reasons << "room_category_ambiguity" if ambiguity
        reasons << "incompatible_room_categories" if incompatible
        reasons << "different_apartment_bedrooms" if contradiction
        outcome = if (distance && distance > 0.1) || incompatible || contradiction || score <= 3
          reasons << "insufficient_score" if score <= 3
          "separate"
        elsif score >= 7 && distance && !ambiguity
          reasons << "merge_threshold"
          "merge"
        else
          reasons << "review_score"
          "review"
        end
        {"al_number" => @number, "listing_ids" => [a.raw["id"], b.raw["id"]],
         "score" => score, "outcome" => outcome, "reasons" => reasons}
      end

      def cross_pairs(a, b)
        a.product(b).map { |left, right| @pairs.fetch([left.raw["id"], right.raw["id"]].sort) }
      end

      def complete_link!
        loop do
          eligible = groups.combination(2).filter_map do |a, b|
            pairs = cross_pairs(a, b)
            next unless pairs.all? { |pair| pair["outcome"] == "merge" }
            [a, b, pairs.map { |pair| pair["score"] }.min, (a + b).map { |e| e.raw["id"] }.sort]
          end
          best = eligible.min_by { |_, _, score, ids| [-score, ids] }
          break unless best
          a, b = best
          groups.delete(a)
          groups.delete(b)
          groups << (a + b).sort_by { |entry| entry.raw["id"] }
        end
        memberships = groups.each_with_index.flat_map { |group, index| group.map { |e| [e.raw["id"], index] } }.to_h
        assessments.each do |pair|
          if pair["outcome"] == "merge" && pair["listing_ids"].map { |id| memberships[id] }.uniq.size > 1
            pair["outcome"] = "review"
            pair["reasons"] << "complete_link_conflict"
          end
        end
        groups.sort_by! { |group| group.map { |e| e.raw["id"] } }
      end
    end
  end
end
