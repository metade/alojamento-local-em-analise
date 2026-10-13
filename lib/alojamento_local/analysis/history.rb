# frozen_string_literal: true

require "csv"
require "fileutils"

module AlojamentoLocal
  module Analysis
    module History
      SUMMARY_HEADERS = %w[run_id source_airbnb_date source_official_register_download_date methodology_version listings licence_groups establishment_estimate generated_at].freeze
      DISTANCE_HEADERS = %w[run_id distance_method range licence_groups].freeze
      REGION_HEADERS = %w[run_id region_method resolution official_region listings].freeze

      module_function

      def verify_local_run!(path, run_id)
        return unless File.exist?(path)
        return unless CSV.foreach(path, headers: true).any? { |row| row["run_id"] == run_id }

        raise "History already exists for immutable local run #{run_id}"
      end

      def append_history(path, row, replace: false)
        values = {"source_airbnb_date" => row[:source_dates][:airbnb_snapshot_date], "source_official_register_download_date" => row[:source_dates][:official_register_download_date]}
        fields = SUMMARY_HEADERS.map { |key| row[key.to_sym] || values[key] }
        write_history_rows(path, SUMMARY_HEADERS, row[:run_id], [fields], replace: replace)
      end

      # Retain other runs' original CSV lines, including their formatting.
      def write_history_rows(path, headers, run_id, rows, replace: false)
        existing = (File.file?(path) && !File.empty?(path)) ? File.read(path) : CSV.generate_line(headers)
        parser = CSV.new(existing, headers: true)
        kept = []
        parser.each do |row|
          if row["run_id"] == run_id
            raise "History already exists for run #{run_id}" unless replace
          else
            kept << parser.line
          end
        end
        raise "Invalid history schema: #{path}" unless parser.headers == headers
        header = existing.lines.first
        output = header + kept.join + rows.map { |row| CSV.generate_line(row) }.join
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, output)
      end

      def distance_range_counts(listings)
        counts = DISTANCE_RANGE_KEYS.to_h { |key| [key, 0] }
        listings.select { |row| row[:license_group_assessment] == "licença repetida em várias localizações" && AlojamentoLocal.coordinates_for(row) }
          .group_by { |row| row[:licensa] }.each_value do |rows|
            distance = AlojamentoLocal.max_cross_cluster_distance_km(rows)
            counts[AlojamentoLocal.distance_range_key(distance)] += 1
          end
        counts
      end

      def append_distance_history(path, run_id, listings, replace: false)
        counts = distance_range_counts(listings)
        rows = DISTANCE_RANGE_KEYS.map { |range| [run_id, "max_cross_cluster_pair_km_v1", range, counts.fetch(range)] }
        write_history_rows(path, DISTANCE_HEADERS, run_id, rows, replace: replace)
      end

      def outside_region_counts(listings)
        listings.each_with_object(Hash.new(0)) do |row, counts|
          next unless row[:license_group_assessment] == "licença oficial fora de Lisboa"

          municipality = row[:official_concelho].to_s.strip
          region = row[:official_region].to_s.strip
          key = if municipality.empty?
            ["municipality_missing", ""]
          elsif region.empty?
            ["region_missing", ""]
          else
            ["resolved", region]
          end
          counts[key] += 1
        end
      end

      def append_outside_region_history(path, run_id, listings, replace: false)
        rows = outside_region_counts(listings).sort_by { |(resolution, region), _| [resolution, region] }.map do |(resolution, region), count|
          [run_id, "official_register_nutsii_v1", resolution, region, count]
        end
        write_history_rows(path, REGION_HEADERS, run_id, rows, replace: replace)
      end

      def historical_comparisons(path, current)
        return [] unless File.exist?(path)
        CSV.foreach(path, headers: true).reject { |old| old["run_id"] == current[:run_id] }.map do |old|
          compatible = old["methodology_version"] == current[:methodology_version]
          {run_id: old["run_id"], status: compatible ? "comparável" : "incompatível — metodologia diferente",
           metrics: compatible ? {listings: old["listings"].to_i, licence_groups: old["licence_groups"].to_i, establishment_estimate: old["establishment_estimate"].to_i} : {}}
        end
      end
    end
  end
end
