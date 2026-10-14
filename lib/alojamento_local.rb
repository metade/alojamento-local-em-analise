require_relative "alojamento_local/public_schema"
require "haversine"
require "set"
require "zeitwerk"

module AlojamentoLocal
  LOADER = Zeitwerk::Loader.new
  LOADER.push_dir(File.join(__dir__, "alojamento_local"), namespace: self)
  # This file defines shared schema constants rather than PublicSchema.
  LOADER.ignore(File.join(__dir__, "alojamento_local/public_schema.rb"))
  LOADER.setup

  ANALYSIS_VERSION = "3.6.0"
  OUTPUT_SCHEMA_VERSION = "6.0.0"
  METHODOLOGY_VERSION = "2.1.0"
  COLLAPSIBLE_ASSESSMENTS = [
    "provável estabelecimento com anúncios múltiplos",
    "licença repetida na mesma localização"
  ].freeze
  DISTANCE_RANGE_KEYS = %w[500_m_1_km 1_2_km 2_5_km over_5_km].freeze

  def self.parse_al_license(string)
    value = string.to_s.strip
    if value =~ /\ARegistration Number:\s*0*(\d+)\s*\/AL\z/i
      return $1.to_i.to_s
    end

    if value =~ /\A0*(\d+)(\/|\s|_|-|\\|&)*al\.?\z/i
      return $1.to_i.to_s
    end

    if value =~ /\Aal(\/|\s|_|-|\\|&)*0*(\d+)\z/i
      return $2.to_i.to_s
    end

    return value.to_i.to_s if /\A0*\d+\z/.match?(value)

    if value =~ /\A0*(\d+)\s*\/\s*20[12]\d\z/
      return $1.to_i.to_s
    end

    nil
  end

  def self.missing_license_assessment(raw_license)
    raw_license.to_s.strip.empty? ? "sem licença" : "sem licença identificável"
  end

  def self.parse_lat_long(string)
    coordinates = string.to_s.split(/\s*;\s*/)
    raise ArgumentError, "Invalid LatLong value: #{string.inspect}" unless coordinates.size == 2

    coordinates.map { |coordinate| Float(coordinate.tr(",", ".")) }
  end

  def self.coordinates_for(listing)
    lat, lng = Float(listing[:lat]), Float(listing[:lng])
    [lat, lng] if lat.finite? && lng.finite? && lat.between?(-90, 90) && lng.between?(-180, 180)
  rescue ArgumentError, TypeError
    nil
  end

  def self.spatial_clusters(listings, threshold_km: 0.5)
    clusters = []

    listings.each do |listing|
      coordinates = coordinates_for(listing)
      unless coordinates
        clusters << [listing]
        next
      end
      matching_clusters = clusters.each_index.select do |index|
        clusters[index].any? do |member|
          other = coordinates_for(member)
          other && Haversine.distance(coordinates[0], coordinates[1], other[0], other[1]).to_km <= threshold_km
        end
      end

      if matching_clusters.empty?
        clusters << [listing]
      else
        target = matching_clusters.first
        clusters[target] << listing
        matching_clusters.drop(1).reverse_each do |index|
          clusters[target].concat(clusters.delete_at(index))
        end
      end
    end

    clusters
  end

  def self.max_cross_cluster_distance_km(listings)
    clusters = spatial_clusters(listings)
    raise ArgumentError, "Expected listings in multiple spatial clusters" if clusters.size < 2

    maximum = 0.0
    clusters.combination(2) do |first, second|
      first.each do |left|
        second.each do |right|
          distance = Haversine.distance(left[:lat].to_f, left[:lng].to_f, right[:lat].to_f, right[:lng].to_f).to_km
          maximum = distance if distance > maximum
        end
      end
    end
    maximum
  end

  def self.distance_range_key(distance_km)
    raise ArgumentError, "Distance below 500 metres" if distance_km < 0.5

    return "500_m_1_km" if distance_km < 1
    return "1_2_km" if distance_km < 2
    return "2_5_km" if distance_km <= 5

    "over_5_km"
  end

  def self.license_group_assessment(listings, official_record)
    return missing_license_assessment(listings.first[:licensa_raw]) if listings.first[:licensa].to_s.empty?
    return "licença oficial fora de Lisboa" if official_record && Geography.municipality(official_record["Concelho"]) && Geography.municipality(official_record["Concelho"]) != "Lisboa"
    return "localização observada não identificada" unless listings.all? { |row| coordinates_for(row) }
    return "licença repetida em várias localizações" if listings.size > 1 && spatial_clusters(listings).size > 1
    return "número sem correspondência no RNAL" unless official_record
    return "geografia oficial não identificada" unless Geography.municipality(official_record["Concelho"])
    return "licença única em Lisboa" if listings.size == 1

    room_like = listings.count do |listing|
      [listing[:nome], listing[:room_type], listing[:property_type]].join(" ").match?(
        /room|bed|suite|quarto|dorm|hostel|guesthouse|guest house|hotel|studio|apartment|flat|residenc|residencial/i
      )
    end
    official_lodging = official_record && official_record["Modalidade"].to_s.match?(/Hospedagem|Hostel|Quartos/i)

    if official_lodging || room_like >= listings.size * 0.5
      "provável estabelecimento com anúncios múltiplos"
    else
      "licença repetida na mesma localização"
    end
  end

  def self.establishment_estimate(listings)
    collapsed_rows = listings.group_by { |listing| listing[:licensa] }.sum do |license, group|
      next 0 if license.to_s.empty?
      next 0 unless COLLAPSIBLE_ASSESSMENTS.include?(group.first[:license_group_assessment])

      group.size - 1
    end

    listings.size - collapsed_rows
  end

  def self.licensed_als(source_path = "data_sources/Estabelecimentos_de_Alojamento_Local.csv")
    Analysis::PreparedSources::Official.new(source_path).classification_lookup
  end

  def self.stats(data, header = "", include_establishment_estimate: false)
    puts "#{data.size} listagens de AirBnb"
    if include_establishment_estimate
      puts "#{establishment_estimate(data)} ALs/estabelecimentos prováveis após deduplicação (estimativa)"
    end

    missing_license_type = {
      nil: data.count { |l| l[:licensa_raw].nil? },
      exempt: data.count { |l| l[:licensa_raw] =~ /Exempt/i },
      others: data.count { |l| l[:license_status] =~ /sem licença/ && !(l[:licensa_raw].nil? || l[:licensa_raw] =~ /Exempt/i) }
    }
    missing_license_summary = [
      "#{missing_license_type[:nil]} sem licença",
      "#{missing_license_type[:exempt]} isentos(?)",
      "#{missing_license_type[:others]} não reconhecidos"
    ].join(", ")

    puts "#{data.count { |l| l[:license_status].blank? }} com licença AL válida"
    puts "#{data.count { |l| l[:license_status] =~ /sem licença/ }} com licença não reconhecida (#{missing_license_summary})"
    distinct_location_count = data.count { |listing| listing[:spatial_cluster_count].to_i > 1 }
    puts "#{distinct_location_count} em que o mesmo número de licença aparece em locais distintos"
    puts "#{data.count { |l| l[:license_status] =~ /distancia/ }} em que a licença AL é numa outra localidade"
  end

  def self.dates(data)
    {
      airbnb_snapshot_date: data.map { |row| row[:airbnb_date] }.compact.max&.to_s,
      official_register_date: data.map { |row| row[:official_date] }.compact.max&.to_s
    }
  end
end
