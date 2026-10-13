# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"

module AlojamentoLocal
  module Analysis
    class OutputWriter
      LISTING_HEADERS = %i[fonte licensa licensa_raw license_status url bairro nome lat lng room_type property_type quartos host_id airbnb_date official_date official_name official_address official_concelho official_modalidade official_capacity distance_km spatial_cluster_count license_group_assessment].freeze
      GROUP_HEADERS = %i[licensa licence_raw_examples listings spatial_locations classification official_name official_concelho official_modalidade establishment_estimate].freeze

      def initialize(result:, path:)
        @result = result
        @path = path
      end

      def generate_data
        FileUtils.mkdir_p(@path)
        if public?
          @snapshot = @result.public_snapshot
          write_json(PublicSnapshot::FILE, @snapshot.to_h)
        else
          write_local_outputs
        end
      end

      def generate_report
        arguments = public? ? @snapshot.report_arguments : @result.report_arguments
        File.write(File.join(@path, report_filename), Report.complete_html(*arguments))
      end

      def generate_pdf
        html = File.join(@path, report_filename)
        pdf = File.join(@path, "report.pdf")
        system("wkhtmltopdf", "--quiet", html, pdf) || system("weasyprint", html, pdf)
      end

      private

      def public?
        @result.metadata.fetch(:mode) == "public"
      end

      def report_filename
        public? ? "report.html" : "report_local.html"
      end

      def write_local_outputs
        write_json("registration_metrics.json", @result.registration_metrics)
        listings = @result.listings.map { |listing| LISTING_HEADERS.to_h { |header| [header, listing[header]] } }
        write_csv("listings_detailed.csv", listings)
        groups = @result.licence_groups.map { |group| group.slice(*GROUP_HEADERS) }
        write_csv("licence_groups_detailed.csv", groups)
        write_csv("freguesias_summary.csv", @result.parish_totals)
        write_json("metadata_local.json", @result.metadata)
        write_json("summary_local.json", @result.summary)
      end

      def write_csv(filename, rows)
        headers = rows.empty? ? PUBLIC_CSV_SCHEMAS.fetch(filename, []) : rows.first.keys
        CSV.open(File.join(@path, filename), "w", write_headers: true, headers: headers) do |csv|
          rows.each { |row| csv << headers.map { |header| row[header] } }
        end
      end

      def write_json(filename, data)
        File.write(File.join(@path, filename), JSON.pretty_generate(data) + "\n")
      end
    end
  end
end
