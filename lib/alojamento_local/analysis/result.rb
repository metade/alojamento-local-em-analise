require "json"
require "digest"

module AlojamentoLocal
  module Analysis
    class Result
      attr_reader :sources, :snapshot

      def initialize(sources:)
        @sources = sources
        @boundaries = Boundaries.new
        assessments = []
        numbered = Hash.new { |hash, number| hash[number] = [] }
        unnumbered = []
        sources.airbnb.entries.each do |entry|
          if entry.declaration.numbers.empty?
            unnumbered << candidate(nil, [entry], [])
          else
            entry.declaration.numbers.each { |number| numbered[number] << entry }
          end
        end
        candidates = numbered.keys.sort_by(&:to_i).flat_map do |number|
          grouping = Grouping.new(number, numbered.fetch(number))
          assessments.concat(grouping.assessments)
          grouping.groups.map { |group| candidate(number, group, grouping.assessments) }
        end + unnumbered
        candidates.group_by { |row| row["al_number"] }.each do |number, group|
          group.each { |row| row["signals"] << "shared_number" } if number && group.size > 1
        end
        @snapshot = {"source_dates" => sources.source_dates,
                     "rnal" => counts(sources.official.lisbon_entries, distinct: true),
                     "listings" => counts(sources.airbnb.entries),
                     "candidates" => candidates.sort_by { |row| row["id"] },
                     "grouping_assessments" => assessments}
        assert_sources!
        CandidateDataset.validate!(@snapshot)
      end

      def summary
        {listings: snapshot.dig("listings", "lisbon", "count"), candidates: snapshot["candidates"].size,
         distinct_al_numbers: snapshot["candidates"].filter_map { |c| c["al_number"] }.uniq.size,
         rnal: snapshot.dig("rnal", "lisbon", "count")}
      end

      private

      def counts(entries, distinct: false)
        count = ->(rows) { distinct ? rows.filter_map(&:number).reject { |number| number == "0" }.uniq.size : rows.size }
        {"lisbon" => {"count" => count.call(entries)},
         "parishes" => (Geography::PARISHES + [nil]).map do |parish|
           {"freguesia" => parish, "count" => count.call(entries.select { |entry| entry.parish == parish })}
         end}
      end

      def candidate(number, entries, assessments)
        ids = entries.map { |entry| entry.raw.fetch("id") }.sort
        coordinate = Grouping.medoid(entries)
        coordinate_parish = @boundaries.parish(coordinate)
        parishes = entries.map(&:parish).uniq
        parish = parishes.first if parishes.size == 1
        record = sources.official.records[number] if number
        match = record&.except("coordinates")&.merge("distance_km" => Grouping.distance(coordinate, record["coordinates"]))
        signals = []
        signals << "partial_licence_extraction" if entries.any? { |entry| entry.declaration.partial? }
        signals << "grouping_review" if assessments.any? { |pair| pair["outcome"] == "review" && (pair["listing_ids"] & ids).any? }
        signals << "observed_parish_disagreement" if coordinate_parish && parishes.compact.any? { |p| p != coordinate_parish }
        if match
          signals << "official_municipality_mismatch" if match["municipality"] && match["municipality"] != "Lisboa"
          signals << "official_parish_mismatch" if match["municipality"] == "Lisboa" && parish && match["freguesia"] && parish != match["freguesia"]
          signals << "official_location_far_from_listings" if match["distance_km"] && match["distance_km"] > 0.5
        end
        {"id" => "candidate-#{Digest::SHA256.hexdigest(JSON.generate([number, ids]))[0, 24]}",
         "al_number" => number, "listing_ids" => ids, "listing_count" => ids.size,
         "raw_licences" => entries.to_h { |entry| [entry.raw["id"], entry.declaration.raw] },
         "freguesia" => parish, "geography" => {"coordinate_freguesia" => coordinate_parish, "airbnb_freguesias" => parishes.compact.sort},
         "registration_status" => if number
                                    record ? "found" : "not_found"
                                  else
                                    entries.first.declaration.status
                                  end,
         "grouping_reason" => (ids.size > 1) ? "scored_merge" : "single_listing", "signals" => signals,
         "official_match" => match}
      end

      def assert_sources!
        actual_ids = snapshot["candidates"].flat_map { |candidate| candidate["listing_ids"] }.uniq.sort
        expected_ids = sources.airbnb.entries.map { |entry| entry.raw["id"] }.sort
        raise "Builder lost source listings" unless actual_ids == expected_ids
        expected = sources.airbnb.entries.flat_map do |entry|
          numbers = entry.declaration.numbers.empty? ? [nil] : entry.declaration.numbers
          numbers.map { |number| [entry.raw["id"], number] }
        end.to_set
        actual = snapshot["candidates"].flat_map { |c| c["listing_ids"].map { |id| [id, c["al_number"]] } }
        raise "Builder changed contributions" unless actual.to_set == expected && actual.size == expected.size
        raise "Builder changed listing summary" unless snapshot["listings"] == counts(sources.airbnb.entries)
        raise "Builder changed RNAL summary" unless snapshot["rnal"] == counts(sources.official.lisbon_entries, distinct: true)
      end
    end
  end
end
