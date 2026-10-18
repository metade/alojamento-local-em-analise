require "set" # standard:disable Lint/RedundantRequireStatement
require "json"
require "digest"

module AlojamentoLocal
  module Analysis
    class DatasetBuilder
      def initialize(sources:)
        @sources = sources
        @boundaries = Boundaries.new
      end

      def build
        grouping = Grouping.new(sources.airbnb.entries, official_records: sources.official.records)
        assessments = grouping.assessments
        @review_ids = assessments.select { |pair| pair["outcome"] == "review" }.flat_map { |pair| pair["listing_ids"] }.to_set
        candidates = grouping.groups.flat_map do |group|
          numbers = group.flat_map { |entry| entry.declaration.numbers }.uniq
          numbers = [nil] if numbers.empty?
          numbers.map { |number| candidate(number, group) }
        end
        candidates.group_by { |row| row["al_number"] }.each do |number, group|
          group.each { |row| row["signals"] << "shared_number" } if number && group.size > 1
        end
        candidates.sort_by! { |row| row["id"] }
        rnal = counts(sources.official.lisbon_entries, distinct: true)
        listings = counts(sources.airbnb.entries)
        summary = CandidateDataset.candidate_aggregates(candidates)
        summary["source_dates"] = sources.source_dates
        summary["lisbon"].merge!("official_count" => rnal.dig("lisbon", "count"), "listings_count" => listings.dig("lisbon", "count"),
          "matched_al_numbers_count" => matched_count(candidates, sources.official.lisbon_entries))
        summary["parishes"].each_with_index do |row, index|
          parish = row.fetch("freguesia")
          row.merge!("matched_al_numbers_count" => matched_count(candidates.select { |c| c["freguesia"] == parish }, sources.official.lisbon_entries.select { |entry| entry.parish == parish }),
            "official_count" => rnal["parishes"][index]["count"], "listings_count" => listings["parishes"][index]["count"])
        end
        assert_sources!({"candidates" => candidates, "rnal" => rnal, "listings" => listings, "summary" => summary})
        CandidateDataset.new(summary_document: summary, details_document: {"candidates" => candidates, "grouping_assessments" => assessments})
      end

      private

      attr_reader :sources

      def counts(entries, distinct: false)
        count = ->(rows) { distinct ? rows.filter_map(&:number).reject { |number| number == "0" }.uniq.size : rows.size }
        {"lisbon" => {"count" => count.call(entries)},
         "parishes" => (Geography::PARISHES + [nil]).map do |parish|
           {"freguesia" => parish, "count" => count.call(entries.select { |entry| entry.parish == parish })}
         end}
      end

      def matched_count(candidates, entries)
        declared = candidates.flat_map { |row| row["raw_licences"].values.flat_map { |raw| Declaration.new(raw).numbers } }.to_set
        official = entries.filter_map(&:number).reject { |number| number == "0" }.to_set
        (declared & official).size
      end

      def candidate(number, entries)
        ids = entries.map { |entry| entry.raw.fetch("id") }.sort
        coordinate = Grouping.medoid(entries)
        coordinate_parish = @boundaries.parish(coordinate)
        parishes = entries.map(&:parish).uniq
        parish = parishes.first if parishes.size == 1
        record = sources.official.records[number] if number
        match = record&.except("coordinates")&.merge("distance_km" => Grouping.distance(coordinate, record["coordinates"]))
        signals = []
        signals << "missing_licence_declaration" if entries.any? { |entry| entry.declaration.status == "absent" }
        signals << "unrecognised_licence_declaration" if entries.any? { |entry| entry.declaration.status == "unrecognised" }
        signals << "partial_licence_extraction" if entries.any? { |entry| entry.declaration.partial? }
        signals << "grouping_review" if ids.any? { |id| @review_ids.include?(id) }
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
                                    ((statuses = entries.map { |entry| entry.declaration.status }.uniq).size == 1) ? statuses.first : "mixed"
                                  end,
         "grouping_reason" => (ids.size > 1) ? "scored_merge" : "single_listing", "signals" => signals,
         "official_match" => match}
      end

      def assert_sources!(document)
        actual_ids = document["candidates"].flat_map { |candidate| candidate["listing_ids"] }.uniq.sort
        expected_ids = sources.airbnb.entries.map { |entry| entry.raw["id"] }.sort
        raise "Builder lost source listings" unless actual_ids == expected_ids
        expected = sources.airbnb.entries.flat_map do |entry|
          numbers = entry.declaration.numbers.empty? ? [nil] : entry.declaration.numbers
          numbers.map { |number| [entry.raw["id"], number] }
        end.to_set
        actual = document["candidates"].flat_map do |c|
          c["raw_licences"].flat_map do |id, raw|
            numbers = Declaration.new(raw).numbers
            [[id, numbers.empty? ? nil : c["al_number"]]]
          end
        end
        raise "Builder changed contributions" unless actual.to_set == expected && actual.size == expected.size
        expected_raw = sources.airbnb.entries.to_h { |entry| [entry.raw["id"], entry.declaration.raw] }
        raise "Builder changed original declarations" unless document["candidates"].all? do |candidate|
          candidate["raw_licences"].all? { |id, raw| expected_raw.fetch(id) == raw }
        end
        raise "Builder changed listing summary" unless document["listings"] == counts(sources.airbnb.entries)
        raise "Builder changed RNAL summary" unless document["rnal"] == counts(sources.official.lisbon_entries, distinct: true)
        summary = document.fetch("summary")
        raise "Builder changed city overlap" unless summary.dig("lisbon", "matched_al_numbers_count") == matched_count(document["candidates"], sources.official.lisbon_entries)
        summary.fetch("parishes").each do |row|
          parish = row.fetch("freguesia")
          candidates = document["candidates"].select { |candidate| candidate["freguesia"] == parish }
          entries = sources.official.lisbon_entries.select { |entry| entry.parish == parish }
          raise "Builder changed parish overlap" unless row["matched_al_numbers_count"] == matched_count(candidates, entries)
        end
      end
    end
  end
end
