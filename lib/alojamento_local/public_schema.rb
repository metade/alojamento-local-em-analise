module AlojamentoLocal
  FORBIDDEN_PUBLIC_FIELDS = %w[
    host_id listing_url url id name title nome licensa licensa_raw
    latitude longitude lat lng address endereco official_address
  ].freeze
end
