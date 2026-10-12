require "csv"
require "json"
require "date"
require_relative "public_schema"
require_relative "registration_metrics"

module AlojamentoLocal
  # Validated public data, independent of report HTML and Liquid. JSON uses
  # string keys; aggregate counts are integers. Identifiable counts describe
  # announcements, not distinct AL numbers (those live in registration_metrics).
  class PublicSnapshot
    COUNT_NAMES = {
      "listings" => "announcements",
      "identifiable_licences" => "announcements_with_identifiable_number",
      "establishments_estimate" => "estimated_establishments"
    }.freeze
    attr_reader :metadata, :summary, :licence_group_aggregates,
      :announcements_by_parish_and_classification, :parish_totals, :registration_metrics

    def initialize(metadata:, summary:, groups:, announcements:, parishes:, metrics:)
      @metadata, @summary, @registration_metrics = metadata, summary, metrics
      @licence_group_aggregates = rename_counts(groups)
      @announcements_by_parish_and_classification = rename_counts(announcements)
      @parish_totals = rename_counts(parishes)
      @published_announcements = announcements
      @published_groups = groups
      instance_variables.each { |name| deep_freeze(instance_variable_get(name)) }
      freeze
    end

    def run_id
      metadata.fetch("run_id")
    end

    # Compatibility at the output boundary preserves the existing CSV/Liquid
    # field names and string values, without exposing them as analytical units.
    def published_announcement_rows
      @published_announcements.map { |row| row.transform_values { |value| value.to_s } }
    end

    def report_arguments
      [metadata, summary, @published_groups, @published_announcements, registration_metrics].map do |value|
        JSON.parse(JSON.generate(value), symbolize_names: true)
      end
    end

    private

    def deep_freeze(value)
      case value
      when Hash
        value.each { |key, item| deep_freeze(key); deep_freeze(item) }
      when Array
        value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end

    def rename_counts(rows)
      rows.map { |row| row.to_h { |key, value| [COUNT_NAMES.fetch(key, key), value] } }
    end

    class Loader
      def initialize
        @json_files = {}
        @snapshots = {}
      end

      def load_json(path)
        @json_files[path] ||= JSON.parse(File.read(path))
      end

      def metadata(path)
        load_json(File.join(path, "metadata.json"))
      end

      # Discovery may skip older runs lacking supported measured sets. A run
      # with supported metrics must pass full validation; errors are not hidden.
      def supported_metrics?(path)
        file = File.join(path, "registration_metrics.json")
        return false unless File.file?(file)
        data = load_json(file)
        data["metric_version"] == RegistrationMetrics::VERSION &&
          RegistrationMetrics::SUPPORTED_METHODOLOGY_VERSIONS.include?(data["methodology_version"])
      end

      def load(path, expected_run_id: File.basename(path))
        @snapshots[[path, expected_run_id]] ||= read_snapshot(path, expected_run_id)
      end

      private

      def read_snapshot(path, expected_run_id)
        meta = metadata(path)
        summary = load_json(File.join(path, "summary.json"))
        metrics = load_json(File.join(path, "registration_metrics.json"))
        raise "Unsupported public output schema" unless meta.fetch("output_schema_version") == "4.0.0"
        raise "Invalid public run" unless meta.fetch("run_id") == expected_run_id && expected_run_id.match?(/\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}\z/)
        raise "Invalid public mode" unless meta.fetch("mode") == "public" && summary.fetch("mode") == "public"
        raise "Public metadata contains a local source path" if meta.dig("source_files", "airbnb", "path") || meta.dig("source_files", "official", "path")
        raise "Forbidden field in public output" if meta.to_s.match?(/host_id|listing_url|licensa_raw|latitude|longitude|official_address/i)
        RegistrationMetrics.validate!(JSON.parse(JSON.generate(metrics), symbolize_names: true))
        %w[run_id source_files methodology_version source_dates].each do |key|
          raise "Metric provenance differs: #{key}" unless metrics.fetch(key) == meta.fetch(key)
        end
        %w[run_id methodology_version source_dates].each do |key|
          raise "Summary provenance differs: #{key}" unless summary.fetch(key) == meta.fetch(key)
        end
        summary.fetch("generated_at")
        dates = meta.fetch("source_dates")
        dates.each_value { |date| Date.iso8601(date) unless date.nil? }
        raise "Run dates differ" unless expected_run_id == "#{dates.fetch('airbnb_snapshot_date')}__#{dates.fetch('official_register_download_date')}"
        %w[airbnb official].each { |source| raise "Missing source URL" unless meta.fetch("source_urls").fetch(source).match?(%r{\Ahttps?://}) }
        %w[analysis_version methodology_version].each { |key| Gem::Version.new(meta.fetch(key)) }
        rows = PUBLIC_CSV_SCHEMAS.to_h { |file, headers| [file, read_csv(File.join(path, file), headers)] }
        validate_aggregates!(summary, metrics, rows)
        PublicSnapshot.new(metadata: meta, summary: summary, groups: rows.fetch("licence_groups.csv"),
          announcements: rows.fetch("listings.csv"), parishes: rows.fetch("freguesias.csv"), metrics: metrics)
      end

      def read_csv(path, headers)
        table = CSV.read(path, headers: true)
        raise "Invalid public schema for #{File.basename(path)}" unless table.headers == headers
        dimensions = headers - %w[listings identifiable_licences establishments_estimate licence_groups spatial_locations]
        keys = []
        table.map do |row|
          raise "Invalid public row for #{File.basename(path)}" unless row.fields.size == headers.size && row.fields.none?(&:nil?)
          raise "Forbidden content in public output #{File.basename(path)}" if row.fields.join(" ").match?(%r{https?://|www\.|/rooms/}i)
          key = dimensions.map { |field| row[field] }
          raise "Duplicate public aggregate in #{File.basename(path)}" if keys.include?(key)
          keys << key
          result = row.to_h.to_h do |field, value|
            unless dimensions.include?(field)
              raise "Invalid public count: #{field}" unless value.match?(/\A\d+\z/)
              value = Integer(value, 10)
            end
            [field, value]
          end
          %w[identifiable_licences establishments_estimate licence_groups spatial_locations].each do |field|
            raise "Public count exceeds announcements: #{field}" if result.key?(field) && result.fetch(field) > result.fetch("listings")
          end
          result
        end
      end

      def validate_aggregates!(summary, metrics, files)
        %w[listings licence_groups official_registers_lisbon establishment_estimate].each do |key|
          value = summary.fetch(key)
          raise "Invalid summary count: #{key}" unless value.is_a?(Integer) && value >= 0
        end
        groups = files.fetch("licence_groups.csv")
        announcements = files.fetch("listings.csv")
        parishes = files.fetch("freguesias.csv")
        measures = metrics.fetch("rows").to_h { |row| [row.fetch("geography"), row] }
        city = measures.fetch("Lisboa")
        raise "City announcement count differs" unless city.fetch("announcements") == summary.fetch("listings")
        raise "City official entry count differs" unless city.fetch("official_entries") == summary.fetch("official_registers_lisbon")
        raise "Licence group total differs" unless groups.sum { |row| row.fetch("licence_groups") } == summary.fetch("licence_groups")
        raise "City estimate differs" unless groups.sum { |row| row.fetch("establishments_estimate") } == summary.fetch("establishment_estimate")
        classifications = groups.group_by { |row| row.fetch("classification") }.transform_values { |rows| rows.sum { |row| row.fetch("licence_groups") } }.reject { |_, count| count.zero? }
        raise "Classification group counts differ" unless classifications == summary.fetch("classifications")
        by_class = ->(rows) { rows.group_by { |row| row.fetch("classification") }.transform_values { |values| values.sum { |row| row.fetch("listings") } } }
        raise "Classification announcement counts differ" unless by_class.call(groups) == by_class.call(announcements)
        expected_parishes = Geography::PARISHES + [Geography::UNKNOWN]
        # Older supported snapshots can omit the empty unknown accounting bucket.
        names = parishes.map { |row| row.fetch("freguesia") }
        raise "Invalid aggregate parishes" unless (expected_parishes - names - [Geography::UNKNOWN]).empty? && (names - expected_parishes).empty?
        raise "Unknown announcement parish" unless announcements.all? { |row| names.include?(row.fetch("freguesia")) }
        parishes.each do |parish|
          name = parish.fetch("freguesia")
          observed = announcements.select { |row| row.fetch("freguesia") == name }
          %w[listings identifiable_licences establishments_estimate].each do |key|
            raise "Parish aggregate differs: #{name} / #{key}" unless observed.sum { |row| row.fetch(key) } == parish.fetch(key)
          end
          measure = measures.fetch(name)
          raise "District announcement metrics differ: #{name}" unless measure.fetch("announcements") == parish.fetch("listings") && measure.fetch("identifiable_number") == parish.fetch("identifiable_licences")
        end
        raise "City aggregate announcements differ" unless parishes.sum { |row| row.fetch("listings") } == city.fetch("announcements") && parishes.sum { |row| row.fetch("identifiable_licences") } == city.fetch("identifiable_number")
        # Only announcements and official entries are additive. Never sum parish
        # distinct numbers or establishment estimates to reconstruct city counts.
        %w[announcements empty_licence unrecognised_licence identifiable_number confirmed_rnal_match official_entries].each do |key|
          raise "Metric parish accounting differs: #{key}" unless metrics.fetch("rows").drop(1).sum { |row| row.fetch(key) } == city.fetch(key)
        end
      end
    end
  end
end
