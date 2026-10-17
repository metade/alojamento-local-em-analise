require "haversine"
require "set" # standard:disable Lint/RedundantRequireStatement
require "zeitwerk"

module AlojamentoLocal
  LOADER = Zeitwerk::Loader.new
  LOADER.push_dir(File.join(__dir__, "alojamento_local"), namespace: self)
  LOADER.setup

  def self.parse_al_license(string)
    # Trim Unicode whitespace and invisible format characters only at the
    # boundaries. Do not join digits or otherwise repair ambiguous content.
    value = string.to_s.strip.gsub(/\A[\p{Space}\p{Cf}]+|[\p{Space}\p{Cf}]+\z/, "")
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

    # Extract one explicit number/AL token from prose. Additional numbers are
    # ambiguous (including bare numbers in a list); never silently pick one.
    if value.scan(/\p{N}+/).size == 1 && value =~ /(?<![\p{L}\p{N}\p{M}\p{Cf}_\/])([0-9]+)\s*\/\s*AL(?![\p{L}\p{N}\p{M}_\/])/i
      return $1.to_i.to_s
    end

    nil
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
end
