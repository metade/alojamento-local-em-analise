module SiteFilters
  def pt_number(value)
    return "???" if value.nil?

    value.to_i.to_s.reverse.gsub(/\d{3}(?=\d)/, "\\0 ").reverse
  end

  def pt_count(value, singular, plural)
    "#{pt_number(value)} #{(value == 1) ? singular : plural}"
  end

  def listing_url(value)
    "https://www.airbnb.com/rooms/#{value}" if value.to_s.match?(/\A\d+\z/)
  end

  def candidate_label(value)
    {
      "absent" => "Sem número declarado", "unrecognised" => "Número não reconhecido",
      "found" => "Número encontrado no RNAL", "not_found" => "Número não encontrado no RNAL",
      "exempt" => "Isenção declarada", "mixed" => "Declarações mistas sem número",
      "missing_licence_declaration" => "Anúncio sem declaração",
      "unrecognised_licence_declaration" => "Anúncio com declaração não reconhecida",
      "scored_merge" => "Anúncios agrupados por evidência concordante",
      "single_listing" => "Um anúncio neste potencial AL",
      "partial_licence_extraction" => "Declaração parcialmente reconhecida",
      "grouping_review" => "Agrupamento por rever",
      "shared_number" => "Número partilhado por vários potenciais AL",
      "official_municipality_mismatch" => "Município oficial diferente do observado",
      "official_parish_mismatch" => "Freguesia oficial diferente da observada",
      "official_location_far_from_listings" => "Localização oficial distante dos anúncios",
      "observed_parish_disagreement" => "Coordenadas e freguesia Airbnb discordantes"
    }.fetch(value, value || "???")
  end
end

Liquid::Template.register_filter(SiteFilters)
