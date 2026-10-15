require "csv"
require "json"
require "date"

module AlojamentoLocal
  # Storage-independent, immutable aggregate data. Aggregate counts are integers;
  # identifiable announcement counts are separate from distinct number sets.
  class PublicSnapshot
    SCHEMA_VERSION = "6.0.0"
    DOCUMENT_SCHEMAS = %w[5.0.0 6.0.0].freeze
    LEGACY_SCHEMA_VERSION = "4.0.0"
    FILE = "snapshot.json"
    COUNT_NAMES = {
      "listings" => "announcements",
      "identifiable_licences" => "announcements_with_identifiable_number",
      "establishments_estimate" => "estimated_establishments"
    }.freeze
    FIELDS = %w[metadata summary licence_group_aggregates announcements_by_parish_and_classification parish_totals registration_metrics].freeze
    TABLES = {
      "licence_groups.csv" => "licence_group_aggregates",
      "listings.csv" => "announcements_by_parish_and_classification",
      "freguesias.csv" => "parish_totals"
    }.freeze
    REQUIRED_FILES = [FILE].freeze
    attr_reader(*FIELDS.map(&:to_sym))

    def self.rename_counts(rows, mapping = COUNT_NAMES)
      rows.map { |row| row.to_h { |key, value| [mapping.fetch(key, key), value] } }
    end

    # The legacy reader and the analysis writer adapt into the same interface.
    def self.from_legacy(metadata:, summary:, groups:, announcements:, parishes:, metrics:)
      new(metadata: metadata, summary: summary, registration_metrics: metrics,
        licence_group_aggregates: rename_counts(groups),
        announcements_by_parish_and_classification: rename_counts(announcements),
        parish_totals: rename_counts(parishes))
    end

    def self.from_document(data)
      raise "Unsupported snapshot schema" unless DOCUMENT_SCHEMAS.include?(data.fetch("schema_version"))
      raise "Invalid snapshot fields" unless data.keys.sort == ["schema_version", *FIELDS].sort
      new(**FIELDS.to_h { |field| [field.to_sym, data.fetch(field)] })
    end

    def initialize(**data)
      raise "Invalid snapshot fields" unless data.keys.map(&:to_s).sort == FIELDS.sort
      data.each { |key, value| instance_variable_set("@#{key}", deep_freeze(value)) }
      freeze
    end

    def run_id
      metadata.fetch("run_id")
    end

    def to_h
      version = metadata.fetch("output_schema_version")
      version = SCHEMA_VERSION unless DOCUMENT_SCHEMAS.include?(version)
      {"schema_version" => version, **FIELDS.to_h { |key| [key, public_send(key)] }}
    end

    def legacy_rows(field)
      self.class.rename_counts(public_send(field), COUNT_NAMES.invert)
    end

    def published_announcement_rows
      legacy_rows("announcements_by_parish_and_classification").map { |row| row.transform_values(&:to_s) }
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

    class Loader
      def initialize
        @json_files = {}
        @snapshots = {}
      end

      def load_json(path)
        @json_files[path] ||= JSON.parse(File.read(path))
      end

      def document(path)
        data = load_json(File.join(path, FILE))
        raise "Unsupported snapshot schema" unless DOCUMENT_SCHEMAS.include?(data.fetch("schema_version"))
        raise "Invalid snapshot fields" unless data.keys.sort == ["schema_version", *FIELDS].sort
        data
      end

      def metadata(path)
        if File.exist?(File.join(path, FILE))
          document(path).fetch("metadata")
        else
          if File.file?(File.join(path, "metadata_local.json"))
            raise "Missing snapshot.json; create a new local analysis rerun to regenerate this report."
          end
          data = load_json(File.join(path, "metadata.json"))
          raise "Missing authoritative snapshot.json" if DOCUMENT_SCHEMAS.include?(data["output_schema_version"])
          data
        end
      end

      # Old runs without compatible measured sets remain available in archives.
      # A consolidated document is always fully validated, never bypassed.
      def supported_metrics?(path)
        return !!load(path) if File.exist?(File.join(path, FILE))
        metadata(path)
        file = File.join(path, "registration_metrics.json")
        return false unless File.file?(file)
        data = load_json(file)
        data["metric_version"] == Analysis::RegistrationMetrics::VERSION &&
          Analysis::RegistrationMetrics::SUPPORTED_METHODOLOGY_VERSIONS.include?(data["methodology_version"])
      end

      def load(path, expected_run_id: File.basename(path), local: false)
        @snapshots[[path, expected_run_id, local]] ||= begin
          if File.exist?(File.join(path, FILE))
            data = document(path)
            snapshot = PublicSnapshot.from_document(data)
            schema = data.fetch("schema_version")
          else
            snapshot = read_legacy(path)
            schema = LEGACY_SCHEMA_VERSION
          end
          Validator.new.validate!(snapshot, expected_run_id: expected_run_id, schema: schema, local: local)
        end
      end

      private

      def read_legacy(path)
        rows = TABLES.to_h { |file, field| [field, read_csv(File.join(path, file), PUBLIC_CSV_SCHEMAS.fetch(file))] }
        PublicSnapshot.from_legacy(metadata: metadata(path), summary: load_json(File.join(path, "summary.json")),
          groups: rows.fetch("licence_group_aggregates"), announcements: rows.fetch("announcements_by_parish_and_classification"),
          parishes: rows.fetch("parish_totals"), metrics: load_json(File.join(path, "registration_metrics.json")))
      end

      def read_csv(path, headers)
        table = CSV.read(path, headers: true)
        raise "Invalid public schema for #{File.basename(path)}" unless table.headers == headers
        dimensions = headers - COUNT_NAMES.keys - %w[licence_groups spatial_locations]
        table.map do |row|
          raise "Invalid public row for #{File.basename(path)}" unless row.fields.size == headers.size && row.fields.none?(&:nil?)
          row.to_h.to_h do |field, value|
            unless dimensions.include?(field)
              raise "Invalid public count: #{field}" unless value.match?(/\A\d+\z/)
              value = Integer(value, 10)
            end
            [field, value]
          end
        end
      end
    end

    class Validator
      def validate!(snapshot, expected_run_id:, schema:, local: false)
        meta, summary, metrics = snapshot.metadata, snapshot.summary, snapshot.registration_metrics
        metadata_fields = %w[run_id source_urls source_dates source_files git_commit analysis_version methodology_version output_schema_version mode]
        summary_fields = %w[run_id source_dates methodology_version listings licence_groups official_registers_lisbon establishment_estimate classifications mode generated_at]
        validate_fields!(meta, metadata_fields, %w[git_worktree_dirty], "metadata")
        validate_fields!(summary, summary_fields, %w[historical_comparisons], "summary")
        validate_fields!(meta.fetch("source_urls"), %w[airbnb official], [], "source URLs")
        raise "Invalid generation timestamp" unless summary.fetch("generated_at").is_a?(String)
        summary.fetch("historical_comparisons", []).each do |comparison|
          validate_fields!(comparison, %w[run_id status metrics], [], "historical comparison")
          values = comparison.fetch("metrics")
          raise "Invalid historical metrics" unless values.is_a?(Hash) && (values.keys - %w[listings licence_groups establishment_estimate]).empty? &&
            values.values.all? { |value| value.is_a?(Integer) && value >= 0 }
        end
        raise "Unsupported public output schema" unless meta.fetch("output_schema_version") == schema
        # Only local reports may use immutable rerun identifiers; public loading
        # always retains the dated-pair identifier and public mode requirements.
        base_run_id = local ? expected_run_id.sub(/__rerun-\d{8}T\d{12}(?:-\d+)?\z/, "") : expected_run_id
        mode = local ? "local" : "public"
        raise "Invalid snapshot run" unless meta.fetch("run_id") == expected_run_id && base_run_id.match?(/\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}\z/)
        raise "Invalid snapshot mode" unless meta.fetch("mode") == mode && summary.fetch("mode") == mode
        raise "Public metadata contains a local source path" if meta.dig("source_files", "airbnb", "path") || meta.dig("source_files", "official", "path")
        raise "Forbidden field in public output" if meta.to_s.match?(/host_id|listing_url|licensa_raw|latitude|longitude|official_address/i)
        Analysis::RegistrationMetrics.validate!(JSON.parse(JSON.generate(metrics), symbolize_names: true))
        %w[run_id source_files methodology_version source_dates].each do |key|
          raise "Metric provenance differs: #{key}" unless metrics.fetch(key) == meta.fetch(key)
        end
        %w[run_id methodology_version source_dates].each do |key|
          raise "Summary provenance differs: #{key}" unless summary.fetch(key) == meta.fetch(key)
        end
        summary.fetch("generated_at")
        dates = meta.fetch("source_dates")
        dates.each_value { |date| Date.iso8601(date) unless date.nil? }
        raise "Run dates differ" unless base_run_id == "#{dates.fetch('airbnb_snapshot_date')}__#{dates.fetch('official_register_download_date')}"
        %w[airbnb official].each { |source| raise "Missing source URL" unless meta.fetch("source_urls").fetch(source).match?(%r{\Ahttps?://}) }
        %w[analysis_version methodology_version].each { |key| Gem::Version.new(meta.fetch(key)) }
        TABLES.each do |file, field|
          headers = PUBLIC_CSV_SCHEMAS.fetch(file).map { |key| COUNT_NAMES.fetch(key, key) }
          validate_rows!(snapshot.public_send(field), headers, field)
        end
        validate_aggregates!(snapshot)
        snapshot
      end

      private

      def validate_fields!(data, required, optional, label)
        raise "Invalid #{label} schema" unless data.is_a?(Hash) && (required - data.keys).empty? && (data.keys - required - optional).empty?
      end

      def validate_rows!(rows, headers, field)
        raise "Invalid aggregate table: #{field}" unless rows.is_a?(Array)
        dimensions = headers - COUNT_NAMES.values - %w[licence_groups spatial_locations]
        seen = Set.new
        rows.each do |row|
          raise "Invalid aggregate schema: #{field}" unless row.is_a?(Hash) && row.keys.sort == headers.sort
          raise "Invalid aggregate dimension: #{field}" unless dimensions.all? { |key| row[key].is_a?(String) && !row[key].empty? }
          raise "Forbidden content in public output #{field}" if dimensions.any? { |key| row[key].match?(%r{https?://|www\.|/rooms/}i) }
          raise "Duplicate public aggregate in #{field}" unless seen.add?(dimensions.map { |key| row[key] })
          (headers - dimensions).each do |key|
            value = row[key]
            raise "Invalid public count: #{key}" unless value.is_a?(Integer) && value >= 0
          end
          (headers - dimensions).each do |key|
            raise "Public count exceeds announcements: #{key}" if row.fetch(key) > row.fetch("announcements")
          end
        end
      end

      def validate_aggregates!(snapshot)
        summary = snapshot.summary
        metrics = snapshot.registration_metrics
        %w[listings licence_groups official_registers_lisbon establishment_estimate].each do |key|
          value = summary.fetch(key)
          raise "Invalid summary count: #{key}" unless value.is_a?(Integer) && value >= 0
        end
        groups = snapshot.licence_group_aggregates
        announcements = snapshot.announcements_by_parish_and_classification
        parishes = snapshot.parish_totals
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
        # Older supported snapshots can omit the empty unknown accounting bucket.
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
