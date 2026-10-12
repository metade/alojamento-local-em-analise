module AlojamentoLocal
  PUBLIC_CSV_SCHEMAS = {
    "listings.csv" => %w[freguesia classification listings identifiable_licences establishments_estimate],
    "licence_groups.csv" => %w[classification official_municipality official_type licence_groups listings spatial_locations establishments_estimate],
    "freguesias.csv" => %w[freguesia listings identifiable_licences establishments_estimate]
  }.freeze
  FORBIDDEN_PUBLIC_FIELDS = %w[
    host_id listing_url url id name title nome licensa licensa_raw
    latitude longitude lat lng address endereco official_address
  ].freeze
end
