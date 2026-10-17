require "csv"
require "date"
require "digest"

module AlojamentoLocal
  module Analysis
    module PreparedSources
      Entry = Struct.new(:raw, :number, :municipality, :parish, :coordinates, :declaration, keyword_init: true)

      def self.parish(value)
        result = Geography.parish(value)
        result unless result == Geography::UNKNOWN
      end

      def self.read(path, required)
        table = CSV.read(path, headers: true, encoding: "bom|utf-8")
        raise ArgumentError, "Duplicate source columns in #{path}" unless table.headers.uniq == table.headers
        missing = required - table.headers
        raise ArgumentError, "Missing source columns in #{path}: #{missing.join(", ")}" unless missing.empty?
        table.map(&:to_h)
      end

      class Official
        attr_reader :entries, :by_number, :lisbon_entries, :records

        def initialize(path)
          @entries = PreparedSources.read(path, %w[NrRNAL Concelho Freguesia LatLong Modalidade NUTSII]).map do |raw|
            coordinates = begin
              lat, lng = AlojamentoLocal.parse_lat_long(raw["LatLong"])
              AlojamentoLocal.coordinates_for(lat: lat, lng: lng)
            rescue ArgumentError
              nil
            end
            Entry.new(raw: raw.freeze, number: AlojamentoLocal.parse_al_license(raw["NrRNAL"]),
              municipality: Geography.municipality(raw["Concelho"]),
              parish: PreparedSources.parish(raw["Freguesia"]), coordinates: coordinates).freeze
          end.freeze
          @by_number = entries.reject { |entry| entry.number.nil? || entry.number == "0" }.group_by(&:number)
          @lisbon_entries = entries.select { |entry| entry.municipality == "Lisboa" }.freeze
          @records = by_number.to_h do |number, group|
            municipalities = group.filter_map(&:municipality)
            municipality = consensus(municipalities)
            parish = consensus(group.map { |e| normalized_parish(e) })
            coordinates = consensus(group.map(&:coordinates))
            if municipalities.map { |value| Geography.key(value) }.uniq.size > 1
              parish = coordinates = nil
            end
            record = {"municipality" => municipality, "freguesia" => parish,
                      "type" => consensus(group.map { |e| clean(e.raw["Modalidade"]) }),
                      "district" => consensus(group.map { |e| clean(e.raw["NUTSII"]) }),
                      "coordinates" => coordinates}
            [number, record]
          end
        end

        private

        def clean(value)
          value = value.to_s.unicode_normalize(:nfc).strip
          value unless value.empty?
        end

        def normalized_parish(entry)
          return entry.parish if entry.municipality == "Lisboa"
          clean(entry.raw["Freguesia"])
        end

        def consensus(values)
          values = values.compact.group_by { |value| value.is_a?(String) ? Geography.key(value) : value }.values
          return values.first&.min if values.size <= 1
          nil
        end
      end

      class Airbnb
        attr_reader :entries
        REQUIRED = %w[id license neighbourhood_group_cleansed neighbourhood_cleansed latitude longitude name description host_id room_type property_type bedrooms].freeze

        def initialize(path)
          rows = PreparedSources.read(path, REQUIRED)
          retained = rows.select { |raw| Geography.municipality(raw["neighbourhood_group_cleansed"]) == "Lisboa" }
          invalid = retained.select { |raw| !raw["id"].to_s.match?(/\A[1-9][0-9]*\z/) }
          duplicate = retained.group_by { |raw| raw["id"] }.select { |_, group| group.size > 1 }.keys
          unless invalid.empty? && duplicate.empty?
            raise ArgumentError, "Invalid or duplicate listing IDs in #{path}: invalid=#{invalid.map { |row| row["id"] }.inspect}, duplicates=#{duplicate.inspect}"
          end
          @entries = retained.sort_by { |raw| raw.fetch("id") }.map do |raw|
            Entry.new(raw: raw.freeze, municipality: "Lisboa",
              parish: PreparedSources.parish(raw["neighbourhood_cleansed"]),
              coordinates: AlojamentoLocal.coordinates_for(lat: raw["latitude"], lng: raw["longitude"]),
              declaration: Declaration.new(raw["license"])).freeze
          end.freeze
        end
      end

      class Pair
        attr_reader :airbnb, :official, :source_hashes, :manifests

        def initialize(airbnb_path: nil, official_path: nil)
          raise ArgumentError, "Provide both source paths or neither" if airbnb_path.nil? != official_path.nil?
          airbnb_path, official_path = Data.local_paths! if airbnb_path.nil?
          @paths = [airbnb_path, official_path]
          @manifests = @paths.map { |path| Data.manifest(path) }
          @source_hashes = @manifests.map { |record| record.fetch("sha256") }.freeze
          verify_unchanged!
          @airbnb = Airbnb.new(airbnb_path)
          @official = Official.new(official_path)
        end

        def source_dates
          {"airbnb_snapshot_date" => manifests[0].fetch("archive_date"),
           "airbnb_fetched_on" => manifests[0]["fetched_on"], "rnal_fetched_on" => manifests[1]["fetched_on"]}
        end

        def identifier
          manifests.map { |record| record.fetch("source_file_date") }.join("__")
        end

        def verify_unchanged!
          raise "Source bytes changed during analysis" unless source_hashes == current_hashes
        end

        private

        def current_hashes
          @paths.map { |path| Digest::SHA256.file(path).hexdigest }
        end
      end
    end
  end
end
