require_relative "alojamento_local/public_schema"
require_relative "alojamento_local/geography"
require "haversine"
require "set"
require "erb"

module AlojamentoLocal
  autoload :Analysis, File.expand_path("alojamento_local/analysis", __dir__)
  autoload :PublicSnapshot, File.expand_path("alojamento_local/public_snapshot", __dir__)

  ANALYSIS_VERSION = "3.4.0"
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

  module Report
    module_function

    def complete_html(metadata, summary, groups, freguesias, metrics)
      html(metadata, summary, groups, freguesias).sub("</body></html>", metrics_section(metrics, metadata: metadata) + historical_section(summary) + "</body></html>")
    end

    def illustrative_anomalies
      [
        {
          signal: "Sem licença identificável",
          pattern: "Um anúncio não apresenta um número que possa ser normalizado como registo AL.",
          reading: "É um sinal para verificação; pode refletir um campo vazio, uma isenção ou um formato não reconhecido."
        },
        {
          signal: "Provável estabelecimento com anúncios múltiplos",
          pattern: "Vários anúncios com a mesma licença aparecem agrupados na mesma zona e descrevem quartos ou unidades.",
          reading: "Pode corresponder a um único estabelecimento com várias ofertas, não a várias licenças independentes."
        },
        {
          signal: "Licença repetida em várias localizações",
          pattern: "A mesma licença normalizada surge em agrupamentos espaciais distintos.",
          reading: "É uma possível reutilização ou divergência que requer confirmação no registo oficial."
        },
        {
          signal: "Licença oficial fora de Lisboa",
          pattern: "A licença é encontrada no registo oficial, mas o concelho oficial não é Lisboa.",
          reading: "A diferença pode resultar de localização, cobertura do snapshot ou qualidade dos dados; não prova uma infração."
        },
        {
          signal: "Possível divergência de localização",
          pattern: "A localização aproximada do anúncio não é consistente com a localização indicada no registo.",
          reading: "A comparação é indicativa e deve ser validada sem divulgar coordenadas ou endereços."
        }
      ]
    end

    def metrics_section(metrics, metadata: {})
      safe = ->(value) { ERB::Util.html_escape(value.to_s) }
      metrics_file = consolidated_report?(metadata) ? "snapshot.json" : "registration_metrics.json"
      headers = Analysis::RegistrationMetrics::COUNTS
      rows = metrics[:rows].map { |row| "<tr><th>#{safe.call(row[:geography])}</th>#{headers.map { |key| "<td>#{row[key.to_sym]}</td>" }.join}</tr>" }.join
      definitions = metrics[:definitions].map { |key, value| "<dt>#{safe.call(key)}</dt><dd>#{safe.call(value)}</dd>" }.join
      "<section><h2>Números distintos e anúncios</h2><p>Métricas #{safe.call(metrics[:metric_version])}; unidades e definições em #{safe.call(metrics_file)}.</p><table><thead><tr><th>Geografia</th>#{headers.map { |key| "<th>#{safe.call(key)}</th>" }.join}</tr></thead><tbody>#{rows}</tbody></table><dl>#{definitions}</dl></section>"
    end

    def historical_section(summary)
      rows = summary[:historical_comparisons].map do |item|
        metrics = item[:metrics]
        "<tr><td>#{ERB::Util.html_escape(item[:run_id].to_s)}</td><td>#{ERB::Util.html_escape(item[:status].to_s)}</td><td>#{metrics[:listings] || '—'}</td><td>#{metrics[:licence_groups] || '—'}</td></tr>"
      end.join
      "<section><h2>Comparação histórica</h2><table><thead><tr><th>Run</th><th>Estado</th><th>Listagens</th><th>Grupos de licença</th></tr></thead><tbody>#{rows.empty? ? '<tr><td colspan=\"4\">Sem runs anteriores.</td></tr>' : rows}</tbody></table><p>Comparações incompatíveis são identificadas quando a versão da metodologia muda.</p></section>"
    end

    def consolidated_report?(metadata)
      metadata[:mode] == "public" && PublicSnapshot::DOCUMENT_SCHEMAS.include?(metadata[:output_schema_version])
    end

    def html(metadata, summary, groups, freguesias)
      safe = ->(value) { ERB::Util.html_escape(value.to_s) }
      data_reference = consolidated_report?(metadata) ? "<a href='snapshot.json'>snapshot.json</a>" : "<code>metadata.json</code>"
      labels = summary[:classifications]
      rows = groups.map { |g| "<tr><td>#{safe.call(g[:classification])}</td><td>#{safe.call(g[:official_municipality])}</td><td>#{safe.call(g[:official_type])}</td><td>#{g[:licence_groups]}</td><td>#{g[:listings]}</td><td>#{g[:spatial_locations]}</td></tr>" }.join
      freg = freguesias.map { |r| "<tr><td>#{safe.call(r[:freguesia])}</td><td>#{safe.call(r[:classification])}</td><td>#{r[:listings]}</td><td>#{r[:identifiable_licences]}</td><td>#{r[:establishments_estimate]}</td></tr>" }.join
      examples = illustrative_anomalies.map do |example|
        "<tr><th scope='row'>#{safe.call(example[:signal])}</th><td>#{safe.call(example[:pattern])}</td><td>#{safe.call(example[:reading])}</td></tr>"
      end.join
      "<!doctype html><html lang='pt'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Alojamento Local em Lisboa — #{safe.call(summary[:run_id])}</title><style>body{font:16px system-ui;max-width:1200px;margin:auto;padding:1rem;color:#243447}header{background:#123;padding:1.5rem;color:white;border-radius:12px}section{margin:1.5rem 0}table{border-collapse:collapse;width:100%;display:block;overflow:auto}th,td{padding:.5rem;border-bottom:1px solid #ddd;text-align:left;vertical-align:top}th{background:#edf2f7}.cards{display:flex;flex-wrap:wrap;gap:1rem}.card{padding:1rem;background:#edf2f7;border-radius:10px;min-width:145px}.bar{background:#2878c8;color:white;padding:.35rem;margin:.3rem 0;border-radius:4px}@media print{body{font-size:11px}header{print-color-adjust:exact}.no-print{display:none}}@media(max-width:600px){.cards{display:grid;grid-template-columns:1fr 1fr}}</style><body><header><h1>Alojamento Local em Lisboa</h1><p>Run #{safe.call(summary[:run_id])} · modo #{safe.call(summary[:mode])} · gerado em #{safe.call(summary[:generated_at])}</p><p>Indicador para verificação oficial</p></header><section><h2>Resumo</h2><div class='cards'><div class='card'><b>#{summary[:listings]}</b><br>listagens</div><div class='card'><b>#{summary[:licence_groups]}</b><br>grupos de licença</div><div class='card'><b>#{summary[:establishment_estimate]}</b><br>estimativa de estabelecimentos</div></div>#{labels.map { |label,count| "<div class='bar' style='width:#{[count * 100 / [summary[:licence_groups],1].max,100].min}%'>#{safe.call(label)}: #{count}</div>" }.join}</section><section><h2>Grupos de licenças (agregado)</h2><table><thead><tr><th>Classificação</th><th>Concelho oficial</th><th>Tipo oficial</th><th>Grupos</th><th>Listagens</th><th>Localizações</th></tr></thead><tbody>#{rows}</tbody></table></section><section><h2>Por freguesia e classificação</h2><table><thead><tr><th>Freguesia</th><th>Classificação</th><th>Listagens</th><th>Licenças identificáveis</th><th>Estimativa</th></tr></thead><tbody>#{freg}</tbody></table></section><section><h2>Exemplos ilustrativos</h2><p>Os exemplos seguintes são sintéticos e servem apenas para explicar os sinais. Não correspondem a anúncios, operadores, números de licença, endereços ou casos individuais.</p><table><thead><tr><th>Sinal</th><th>Padrão ilustrativo</th><th>Leitura prudente</th></tr></thead><tbody>#{examples}</tbody></table></section><section><h2>Proveniência e método</h2><p>Fontes: <a href='#{safe.call(metadata[:source_urls][:airbnb])}'>Airbnb</a> e <a href='#{safe.call(metadata[:source_urls][:official])}'>registo oficial</a>. Datas e hashes SHA-256 estão em #{data_reference}. Metodologia #{safe.call(metadata[:methodology_version])}; análise #{safe.call(metadata[:analysis_version])}.</p><p>As classificações são indicadores analíticos e não conclusões legais. Requerem verificação junto das fontes oficiais.</p></section></body></html>"
    end
  end
end
