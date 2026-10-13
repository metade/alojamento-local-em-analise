# frozen_string_literal: true

require "date"
require "haversine"

module AlojamentoLocal
  module Analysis
    class Classifier
      def initialize(sources)
        @sources = sources
        @official = sources.official.classification_lookup
      end

      def classify
        listings = @sources.airbnb.entries.map { |entry| listing_row(entry) }
        assess_groups(listings)
        [listings, @official]
      end

      def self.parse_date(value)
        Date.parse(value) if value && !value.empty?
      rescue ArgumentError
        nil
      end

      def self.status(record, distance, count)
        return "sem licença identificável" unless record

        values = []
        values << "licença fora da localização (distancia #{distance})" if distance && distance > 1
        values << "licença reutilizada #{count}" if count > 1
        values.join(";")
      end

      private

      def listing_row(entry)
        row = entry.raw
        record = @official[entry.number]
        distance = distance_from_register(row, record)
        {
          fonte: "airbnb", licensa: entry.number, licensa_raw: row["license"],
          license_status: self.class.status(record, distance, @sources.airbnb.licence_counts[entry.number]),
          url: row["listing_url"], bairro: entry.parish, nome: row["name"], lat: row["latitude"], lng: row["longitude"],
          room_type: row["room_type"], property_type: row["property_type"], quartos: row["bedrooms"], host_id: row["host_id"],
          airbnb_date: self.class.parse_date(row["last_scraped"]), official_date: record && self.class.parse_date(record["DataRegisto"]),
          official_name: record && record["Denominacao"], official_address: record && record["Endereco"],
          official_concelho: record && record["Concelho"], official_region: record && record["NUTSII"],
          official_modalidade: record && record["Modalidade"], official_capacity: record && record["NrUtentes"], distance_km: distance
        }
      end

      def distance_from_register(row, record)
        return unless record && record["LatLong"] && !record["LatLong"].empty?
        return unless AlojamentoLocal.coordinates_for({lat: row["latitude"], lng: row["longitude"]})

        official_lat, official_lng = AlojamentoLocal.parse_lat_long(record["LatLong"])
        Haversine.distance(official_lat, official_lng, row["latitude"].to_f, row["longitude"].to_f).to_km
      end

      def assess_groups(listings)
        listings.group_by { |row| row[:licensa] }.each do |license, members|
          next if license.to_s.empty?

          cluster_count = AlojamentoLocal.spatial_clusters(members).size
          assessment = AlojamentoLocal.license_group_assessment(members, @official[license])
          members.each do |row|
            row[:spatial_cluster_count] = cluster_count
            row[:license_group_assessment] = assessment
          end
        end
        listings.each do |row|
          row[:spatial_cluster_count] ||= 1
          row[:license_group_assessment] ||= AlojamentoLocal.missing_license_assessment(row[:licensa_raw])
        end
      end
    end
  end
end
