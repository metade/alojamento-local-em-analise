require "csv"
require "date"
require "digest"

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
        attr_reader :airbnb, :official, :source_hashes

        def initialize(airbnb_path: nil, official_path: nil)
          raise ArgumentError, "Provide both source paths or neither" if airbnb_path.nil? != official_path.nil?

          airbnb_path, official_path = Data.local_paths! if airbnb_path.nil?
          @airbnb_path = airbnb_path
          @official_path = official_path
          @source_hashes = current_hashes.freeze
          @airbnb = Airbnb.new(airbnb_path)
          @official = Official.new(official_path)
        end

        def source_dates
          @source_dates ||= {
            airbnb_snapshot_date: filename_date(@airbnb_path) || airbnb.entries.filter_map { |entry| parse_date(entry.raw["last_scraped"]) }.max&.to_s,
            official_register_download_date: filename_date(@official_path) || File.mtime(@official_path).to_date.to_s
          }
        end

        def provenance
          {
            source_urls: {airbnb: Data.airbnb_url(source_dates[:airbnb_snapshot_date]), official: Data::OFFICIAL_URL},
            source_dates: source_dates, source_files: {airbnb: {sha256: source_hashes[0]}, official: {sha256: source_hashes[1]}}
          }
        end

        def identifier
          source_dates.values_at(:airbnb_snapshot_date, :official_register_download_date).join("__")
        end

        def verify_unchanged!
          raise "Source bytes changed during analysis" unless source_hashes == current_hashes
        end

        private

        def current_hashes
          [@airbnb_path, @official_path].map { |path| Digest::SHA256.file(path).hexdigest }
        end

        def filename_date(path)
          File.basename(path)[/(\d{4}-\d{2}-\d{2})/, 1]
        end

        def parse_date(value)
          Date.parse(value) if value && !value.empty?
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
