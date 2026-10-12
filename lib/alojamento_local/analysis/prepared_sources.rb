require "csv"
require_relative "../geography"
require_relative "../analysis"

module AlojamentoLocal
  module Analysis
    # Run-scoped source preparation. Entries retain raw fields; indices never
    # discard duplicates. Only the separate classification view resolves conflicts.
    module PreparedSources
      Entry = Struct.new(:raw, :number, :municipality, :parish, keyword_init: true)

      class Official
        attr_reader :entries, :by_number, :lisbon_entries, :lisbon_by_parish, :classification_lookup

        def initialize(path)
          @entries = CSV.foreach(path, headers: true).map do |row|
            raw = row.to_h.freeze
            Entry.new(raw: raw, number: AlojamentoLocal.parse_al_license(raw["NrRNAL"]),
              municipality: Geography.municipality(raw["Concelho"]), parish: Geography.parish(raw["Freguesia"])).freeze
          end.freeze
          @by_number = entries.group_by(&:number).transform_values(&:freeze).freeze
          @lisbon_entries = entries.select { |entry| entry.municipality == "Lisboa" }.freeze
          @lisbon_by_parish = lisbon_entries.group_by(&:parish).transform_values(&:freeze).freeze
          @classification_lookup = by_number.filter_map do |number, group|
            next unless number
            locations = group.map { |entry| [entry.municipality, entry.parish, entry.raw["LatLong"]] }.uniq
            record = group.first.raw.dup
            record["Concelho"] = group.first.municipality
            if locations.size > 1
              record["Concelho"] = nil
              record["LatLong"] = nil
            end
            [number, record.freeze]
          end.to_h.freeze
        end
      end

      class Airbnb
        attr_reader :entries, :licence_counts

        def initialize(path)
          @licence_counts = Hash.new(0)
          @entries = CSV.foreach(path, headers: true).filter_map do |row|
            raw = row.to_h
            municipality = Geography.municipality(raw["neighbourhood_group_cleansed"])
            next unless municipality == "Lisboa"
            number = AlojamentoLocal.parse_al_license(raw["license"])
            Entry.new(raw: raw.freeze, number: number, municipality: municipality,
              parish: Geography.parish(raw["neighbourhood_cleansed"])).freeze
          end.freeze
          # Reuse and classification must describe the same retained population.
          entries.each { |entry| licence_counts[entry.number] += 1 }
          @licence_counts.freeze
        end
      end

      class Pair
        attr_reader :airbnb, :official

        def initialize(airbnb_path:, official_path:)
          @airbnb = Airbnb.new(airbnb_path)
          @official = Official.new(official_path)
        end
      end
    end
  end
end
