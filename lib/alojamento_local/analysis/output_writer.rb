# frozen_string_literal: true

require "csv"
require "json"

module AlojamentoLocal
  module Analysis
    module OutputWriter
      LISTING_HEADERS = %i[fonte licensa licensa_raw license_status url bairro nome lat lng room_type property_type quartos host_id airbnb_date official_date official_name official_address official_concelho official_modalidade official_capacity distance_km spatial_cluster_count license_group_assessment].freeze
      GROUP_HEADERS = %i[licensa licence_raw_examples listings spatial_locations classification official_name official_concelho official_modalidade establishment_estimate].freeze

      module_function

      def write_report(run_dir, filename, arguments)
        File.write(File.join(run_dir, filename), Report.complete_html(*arguments))
      end

      def detailed_listing_rows(listings)
        listings.map { |listing| LISTING_HEADERS.to_h { |header| [header, listing[header]] } }
      end

      def detailed_group_rows(groups)
        groups.map { |group| group.slice(*GROUP_HEADERS) }
      end

      def write_json_outputs(run_dir, metadata, summary, metadata_filename, summary_filename)
        write_json(File.join(run_dir, metadata_filename), metadata)
        write_json(File.join(run_dir, summary_filename), summary)
      end

      def write_csv(path, rows)
        headers = rows.empty? ? PUBLIC_CSV_SCHEMAS.fetch(File.basename(path), []) : rows.first.keys
        CSV.open(path, "w", write_headers: true, headers: headers) do |csv|
          rows.each { |row| csv << headers.map { |header| row[header] } }
        end
      end

      def generate_pdf_file(run_dir)
        html = File.join(run_dir, "report.html")
        pdf = File.join(run_dir, "report.pdf")
        system("wkhtmltopdf", "--quiet", html, pdf) || system("weasyprint", html, pdf)
      end

      def write_snapshot(run_dir, snapshot)
        write_json(File.join(run_dir, PublicSnapshot::FILE), snapshot.to_h)
      end

      def write_local_outputs(run_dir, result)
        write_json(File.join(run_dir, "registration_metrics.json"), result.registration_metrics)
        write_csv(File.join(run_dir, "listings_detailed.csv"), detailed_listing_rows(result.listings))
        write_csv(File.join(run_dir, "licence_groups_detailed.csv"), detailed_group_rows(result.licence_groups))
        write_csv(File.join(run_dir, "freguesias_summary.csv"), result.parish_totals)
        write_json_outputs(run_dir, result.metadata, result.summary, "metadata_local.json", "summary_local.json")
      end

      def write_json(path, data)
        File.write(path, JSON.pretty_generate(data) + "\n")
      end

      private_class_method :write_json
    end
  end
end
