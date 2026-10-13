# frozen_string_literal: true

require "csv"
require "json"

module AlojamentoLocal
  module Analysis
    module OutputWriter
      LISTING_HEADERS = %i[fonte licensa licensa_raw license_status url bairro nome lat lng room_type property_type quartos host_id airbnb_date official_date official_name official_address official_concelho official_modalidade official_capacity distance_km spatial_cluster_count license_group_assessment].freeze
      GROUP_HEADERS = %i[licensa licence_raw_examples listings spatial_locations classification official_name official_concelho official_modalidade establishment_estimate].freeze

      module_function

      def write_outputs(run_dir:, mode:, listings:, groups:, freguesias:, public_listings:, public_groups:, metadata:, summary:, metrics:)
        if mode == "public"
          snapshot = write_public_snapshot(run_dir, metadata, summary, public_groups, public_listings, freguesias, metrics)
          report_filename = "report.html"
          arguments = snapshot.report_arguments
        else
          write_local_outputs(run_dir, metadata, summary, listings, groups, freguesias, metrics)
          report_filename = "report_local.html"
          arguments = [metadata, summary, public_groups, public_listings, metrics]
        end
        File.write(File.join(run_dir, report_filename), Report.complete_html(*arguments))
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

      def write_public_snapshot(run_dir, metadata, summary, groups, announcements, parishes, metrics)
        inputs = JSON.parse(JSON.generate({metadata: metadata, summary: summary, groups: groups,
          announcements: announcements, parishes: parishes, metrics: metrics}))
        snapshot = PublicSnapshot.from_legacy(**inputs.transform_keys(&:to_sym))
        PublicSnapshot::Validator.new.validate!(snapshot, expected_run_id: metadata.fetch(:run_id), schema: PublicSnapshot::SCHEMA_VERSION)
        write_json(File.join(run_dir, PublicSnapshot::FILE), snapshot.to_h)
        snapshot
      end

      def write_local_outputs(run_dir, metadata, summary, listings, groups, freguesias, metrics)
        write_json(File.join(run_dir, "registration_metrics.json"), metrics)
        write_csv(File.join(run_dir, "listings_detailed.csv"), detailed_listing_rows(listings))
        write_csv(File.join(run_dir, "licence_groups_detailed.csv"), detailed_group_rows(groups))
        write_csv(File.join(run_dir, "freguesias_summary.csv"), freguesias)
        write_json_outputs(run_dir, metadata, summary, "metadata_local.json", "summary_local.json")
      end

      def write_json(path, data)
        File.write(path, JSON.pretty_generate(data) + "\n")
      end

      private_class_method :write_public_snapshot, :write_local_outputs, :write_json
    end
  end
end
