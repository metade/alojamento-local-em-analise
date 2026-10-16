require "json"
require "set"

module AlojamentoLocal
  module PublicSnapshot
    class Validator
      # JSON Schema checks document structure; Ruby checks relationships between values.
      def validate!(snapshot, expected_run_id:)
        base_run_id = validate_run!(snapshot, expected_run_id: expected_run_id)
        validate_provenance!(snapshot, base_run_id)
        validate_tables!(snapshot)
        validate_aggregates!(snapshot)
        snapshot
      end

      private

      def validate_run!(snapshot, expected_run_id:)
        meta = snapshot.fetch("metadata")
        raise "Invalid snapshot run" unless meta.fetch("run_id") == expected_run_id && expected_run_id.match?(/\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}\z/)
        expected_run_id
      end

      def validate_provenance!(snapshot, base_run_id)
        meta, summary, metrics = snapshot.fetch("metadata"), snapshot.fetch("summary"), snapshot.fetch("registration_metrics")
        raise "Forbidden field in public output" if meta.to_s.match?(/host_id|listing_url|licensa_raw|latitude|longitude|official_address/i)
        Analysis::RegistrationMetrics.validate!(JSON.parse(JSON.generate(metrics), symbolize_names: true))
        %w[run_id source_files methodology_version source_dates].each do |key|
          raise "Metric provenance differs: #{key}" unless metrics.fetch(key) == meta.fetch(key)
        end
        %w[run_id methodology_version source_dates].each do |key|
          raise "Summary provenance differs: #{key}" unless summary.fetch(key) == meta.fetch(key)
        end
        dates = meta.fetch("source_dates")
        raise "Run dates differ" unless base_run_id == "#{dates.fetch('airbnb_snapshot_date')}__#{dates.fetch('official_register_download_date')}"
      end

      def validate_tables!(snapshot)
        {
          "licence_group_aggregates" => %w[classification official_municipality official_type],
          "announcements_by_parish_and_classification" => %w[freguesia classification],
          "parish_totals" => %w[freguesia]
        }.each do |field, dimensions|
          seen = Set.new
          snapshot.fetch(field).each do |row|
            raise "Duplicate public aggregate in #{field}" unless seen.add?(dimensions.map { |key| row.fetch(key) })
            (row.keys - dimensions).each do |key|
              raise "Public count exceeds announcements: #{key}" if row.fetch(key) > row.fetch("announcements")
            end
          end
        end
      end

      def validate_aggregates!(snapshot)
        summary = snapshot.fetch("summary")
        metrics = snapshot.fetch("registration_metrics")
        groups = snapshot.fetch("licence_group_aggregates")
        announcements = snapshot.fetch("announcements_by_parish_and_classification")
        parishes = snapshot.fetch("parish_totals")
        measures = metrics.fetch("rows").to_h { |row| [row.fetch("geography"), row] }
        city = measures.fetch("Lisboa")
        raise "City announcement count differs" unless city.fetch("announcements") == summary.fetch("listings")
        raise "City official entry count differs" unless city.fetch("official_entries") == summary.fetch("official_registers_lisbon")
        raise "Licence group total differs" unless groups.sum { |row| row.fetch("licence_groups") } == summary.fetch("licence_groups")
        raise "City estimate differs" unless groups.sum { |row| row.fetch("estimated_establishments") } == summary.fetch("establishment_estimate")
        classifications = groups.group_by { |row| row.fetch("classification") }.transform_values { |rows| rows.sum { |row| row.fetch("licence_groups") } }.reject { |_, count| count.zero? }
        raise "Classification group counts differ" unless classifications == summary.fetch("classifications")
        by_class = ->(rows) { rows.group_by { |row| row.fetch("classification") }.transform_values { |values| values.sum { |row| row.fetch("announcements") } } }
        raise "Classification announcement counts differ" unless by_class.call(groups) == by_class.call(announcements)
        expected_parishes = Geography::PARISHES + [Geography::UNKNOWN]
        # The unknown accounting bucket can be absent when no announcements use it.
        names = parishes.map { |row| row.fetch("freguesia") }
        raise "Invalid aggregate parishes" unless (expected_parishes - names - [Geography::UNKNOWN]).empty? && (names - expected_parishes).empty?
        raise "Unknown announcement parish" unless announcements.all? { |row| names.include?(row.fetch("freguesia")) }
        parishes.each do |parish|
          name = parish.fetch("freguesia")
          observed = announcements.select { |row| row.fetch("freguesia") == name }
          %w[announcements announcements_with_identifiable_number estimated_establishments].each do |key|
            raise "Parish aggregate differs: #{name} / #{key}" unless observed.sum { |row| row.fetch(key) } == parish.fetch(key)
          end
          measure = measures.fetch(name)
          raise "District announcement metrics differ: #{name}" unless measure.fetch("announcements") == parish.fetch("announcements") && measure.fetch("identifiable_number") == parish.fetch("announcements_with_identifiable_number")
        end
        raise "City aggregate announcements differ" unless parishes.sum { |row| row.fetch("announcements") } == city.fetch("announcements") && parishes.sum { |row| row.fetch("announcements_with_identifiable_number") } == city.fetch("identifiable_number")
        # Only announcements and official entries are additive. Never sum parish
        # distinct numbers or establishment estimates to reconstruct city counts.
        %w[announcements empty_licence unrecognised_licence identifiable_number confirmed_rnal_match official_entries].each do |key|
          raise "Metric parish accounting differs: #{key}" unless metrics.fetch("rows").drop(1).sum { |row| row.fetch(key) } == city.fetch(key)
        end
      end
    end
  end
end
