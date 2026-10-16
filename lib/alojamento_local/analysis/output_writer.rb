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
        write_json(PublicSnapshot::FILE, @result.snapshot)
      end

      def generate_diagnostics
        FileUtils.mkdir_p(@path)
        listings = @result.listings.map { |listing| LISTING_HEADERS.to_h { |header| [header, listing[header]] } }
        write_csv("listings_detailed.csv", listings, LISTING_HEADERS)
        groups = @result.licence_groups.map { |group| group.slice(*GROUP_HEADERS) }
        write_csv("licence_groups_detailed.csv", groups, GROUP_HEADERS)
      end

      private

      def write_csv(filename, rows, headers)
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
