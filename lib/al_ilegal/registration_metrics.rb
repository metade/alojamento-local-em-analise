# Aggregate registration sets; source values stay in memory and private outputs.
module AlIlegal
  module Geography
    PARISHES = ["Ajuda", "Alcântara", "Alvalade", "Areeiro", "Arroios", "Avenidas Novas", "Beato", "Belém", "Benfica", "Campo de Ourique", "Campolide", "Carnide", "Estrela", "Lumiar", "Marvila", "Misericórdia", "Olivais", "Parque das Nações", "Penha de França", "Santa Clara", "Santa Maria Maior", "Santo António", "São Domingos de Benfica", "São Vicente"].freeze
    ALIASES = {"Alcntara" => "Alcântara", "Belm" => "Belém", "Misericrdia" => "Misericórdia", "Parque das Naes" => "Parque das Nações", "Penha de Frana" => "Penha de França", "Santo Antnio" => "Santo António", "So Domingos de Benfica" => "São Domingos de Benfica", "So Vicente" => "São Vicente"}.freeze
    UNKNOWN = "Geografia não identificada"
    def self.key(value)
      value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").strip.downcase.gsub(/\s+/, " ")
    end
    def self.municipality(value)
      text = value.to_s.strip
      return nil if text.empty? || key(text).match?(/\A(?:unknown|desconhecid[oa]|nao identificad[oa]|nao disponivel|n\/a|null|nd|-)\z/)
      key(text) == "lisboa" ? "Lisboa" : text
    end
    PARISH_KEYS = PARISHES.to_h { |name| [key(name), name] }.freeze
    def self.parish(value)
      text = ALIASES.fetch(value.to_s.strip, value.to_s.strip)
      PARISH_KEYS.fetch(key(text), UNKNOWN)
    end
  end

  # Calculates distinct RNAL/Airbnb registration sets, their geographic
  # differences, and separate announcement/official-entry counts for Lisbon
  # and its parishes. These aggregates are saved in registration_metrics.json
  # for the report and site; classification and establishment estimates live
  # in the main analysis.
  #
  # Currently rereads and normalizes RNAL and builds an index also prepared by
  # AlIlegal.licensed_als. This path retains every official entry, including
  # duplicates and geographic conflicts, which the classification lookup loses.
  # Consolidate source preparation without losing those records; related count
  # and parish-alias duplication is tracked in TODO.md.
  module RegistrationMetrics
    VERSION = "1.0.0"
    SUPPORTED_METHODOLOGY_VERSION = "2.0.0"
    COUNTS = %w[rnal airbnb intersection rnal_only airbnb_only another_lisbon_parish another_municipality no_national_match unresolved_official_geography announcements empty_licence unrecognised_licence identifiable_number confirmed_rnal_match official_entries].freeze
    DEFINITIONS = {
      sets: "Distinct normalized AL numbers. RNAL: official Concelho=Lisboa and official Freguesia. Airbnb: observed municipality=Lisboa and observed parish. City sets are computed independently, never summed from parishes.",
      differences: "RNAL-only means absent from Airbnb in the same geography, not absent elsewhere. Airbnb-only does not imply absence from national RNAL.",
      difference_priority: "Among Airbnb-only numbers: no national record; unresolved if any matching official record has missing/unknown municipality, unknown Lisbon parish (district scope), or conflicting municipality/parish; otherwise another Lisbon parish or another municipality. Multiple identical entries count once in sets.",
      announcements: "Empty (nil or whitespace), filled unrecognised, identifiable are disjoint and sum to all observed Lisbon announcements. Confirmed match is a subset of identifiable: number present in dated national RNAL, without asserting validity, activity or geography.",
      entries: "Official CSV rows with declared Concelho=Lisboa; duplicates retained in entry counts, deduplicated in number sets. Unparseable official numbers excluded from sets and diagnosed.",
      geography: "Trim, case and accent normalization; explicit aliases for Inside Airbnb's missing accented letters; 24 Lisbon parishes. Missing/unrecognized parishes pooled in Geografia não identificada and excluded from known parish sets; included in city totals. Nonempty nonsentinel national municipality names are accepted as declared, not independently validated.",
      denominators: "Set differences use distinct numbers in the local Airbnb or RNAL set. Announcement counts use observed Lisbon rows. No implicit percentages. Parish totals and establishment estimates are not additive across the city.",
      classification: "Priority: empty/unrecognized; known outside municipality; unresolved observed coordinates; multiple spatial clusters; no national match; unresolved official municipality; single Lisbon match; probable multiple units; repeated same location. Metadados de anfitrião nunca agrupam anúncios. Clusters are connected components of edges <=500m, so chain endpoints may exceed 500m; missing coordinates remain singleton clusters.",
      estimate: "One per matched Lisbon number in either lower-risk same-location category, plus every announcement in all other categories. Calculated independently in each geography; no collapsing unmatched, outside or unresolved cases. Indicator, not legal finding."
    }.freeze

    def self.calculate(listings, official_path)
      records = CSV.foreach(official_path, headers: true).map(&:to_h)
      national = records.group_by { |r| AlIlegal.parse_al_license(r["NrRNAL"]) }
      lisbon = records.select { |r| Geography.municipality(r["Concelho"]) == "Lisboa" }
      rows = [["Lisboa", listings, lisbon]] + (Geography::PARISHES + [Geography::UNKNOWN]).map do |parish|
        [parish, listings.select { |r| r[:bairro] == parish }, lisbon.select { |r| Geography.parish(r["Freguesia"]) == parish }]
      end
      aggregates = rows.map do |name, observed, local_records|
        a = observed.filter_map { |r| r[:licensa] }.to_set
        r = local_records.filter_map { |row| AlIlegal.parse_al_license(row["NrRNAL"]) }.to_set
        # Unknown geography is an accounting bucket, not an asserted local match.
        intersection = name == Geography::UNKNOWN ? Set.new : a & r
        breakdown = Hash.new(0)
        (a - intersection).each do |number|
          matches = national[number]
          category = if !matches
            "no_national_match"
          else
            municipalities = matches.map { |record| Geography.municipality(record["Concelho"]) }.uniq
            parishes = matches.map { |record| Geography.parish(record["Freguesia"]) }.uniq
            if name == Geography::UNKNOWN || municipalities.include?(nil) || municipalities.size > 1 ||
                (municipalities == ["Lisboa"] && name != "Lisboa" && (parishes.include?(Geography::UNKNOWN) || parishes.size > 1))
              "unresolved_official_geography"
            elsif municipalities == ["Lisboa"]
              "another_lisbon_parish"
            else
              "another_municipality"
            end
          end
          breakdown[category] += 1
        end
        {geography: name, rnal: r.size, airbnb: a.size, intersection: intersection.size,
         rnal_only: (r - intersection).size, airbnb_only: (a - intersection).size,
         another_lisbon_parish: breakdown["another_lisbon_parish"], another_municipality: breakdown["another_municipality"],
         no_national_match: breakdown["no_national_match"], unresolved_official_geography: breakdown["unresolved_official_geography"],
         announcements: observed.size, empty_licence: observed.count { |row| row[:licensa_raw].to_s.strip.empty? },
         unrecognised_licence: observed.count { |row| !row[:licensa_raw].to_s.strip.empty? && !row[:licensa] },
         identifiable_number: observed.count { |row| row[:licensa] }, confirmed_rnal_match: observed.count { |row| row[:licensa] && national.key?(row[:licensa]) },
         official_entries: local_records.size}
      end
      result = {metric_version: VERSION, definitions: DEFINITIONS, rows: aggregates,
                diagnostics: {national_entries: records.size, unparseable_official_numbers: national.fetch(nil, []).size,
                  duplicate_number_extra_entries: national.reject { |number, _| number.nil? }.values.sum { |group| group.size - 1 },
                  official_entries_unresolved_municipality: records.count { |record| !Geography.municipality(record["Concelho"]) },
                  lisbon_entries_unresolved_parish: lisbon.count { |record| Geography.parish(record["Freguesia"]) == Geography::UNKNOWN }}}
      validate!(result)
      result
    end

    def self.validate!(data)
      allowed = %i[metric_version definitions rows diagnostics run_id source_files methodology_version source_dates]
      raise "Unexpected metric field" unless (data.keys - allowed).empty?
      raise "Metric definitions differ" unless data[:definitions] == DEFINITIONS
      diagnostic_keys = %i[national_entries unparseable_official_numbers duplicate_number_extra_entries official_entries_unresolved_municipality lisbon_entries_unresolved_parish]
      raise "Invalid diagnostics" unless data[:diagnostics].keys == diagnostic_keys && data[:diagnostics].values.all? { |count| count.is_a?(Integer) && count >= 0 }
      if data[:run_id]
        raise "Invalid metric run" unless data[:run_id].match?(/\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}(?:__m[\d.]+(?:__a[\d.]+)?)?(?:__rerun-\d{8}T\d{12}(?:-\d+)?)?\z/)
        raise "Incompatible metric method" unless data[:methodology_version] == SUPPORTED_METHODOLOGY_VERSION
        raise "Invalid metric dates" unless data[:source_dates].keys == %i[airbnb_snapshot_date official_register_date official_register_download_date] && data[:source_dates].values.all? { |date| date.nil? || date.match?(/\A\d{4}-\d{2}-\d{2}\z/) }
      end
      if data[:source_files]
        raise "Invalid source hashes" unless data[:source_files].keys == %i[airbnb official] && data[:source_files].values.all? { |source| source.keys == [:sha256] && source[:sha256].match?(/\A[0-9a-f]{64}\z/) }
      end
      raise "Unknown metric version" unless data[:metric_version] == VERSION
      raise "Invalid metric geographies" unless data[:rows].map { |row| row[:geography] } == ["Lisboa", *Geography::PARISHES, Geography::UNKNOWN]
      data[:rows].each do |row|
        raise "Invalid metric schema" unless row.keys == [:geography, *COUNTS.map(&:to_sym)]
        raise "Invalid metric count" unless COUNTS.all? { |key| row[key.to_sym].is_a?(Integer) && row[key.to_sym] >= 0 }
        raise "Set accounting mismatch" unless row[:rnal] == row[:rnal_only] + row[:intersection] && row[:airbnb] == row[:airbnb_only] + row[:intersection]
        raise "Difference accounting mismatch" unless row[:airbnb_only] == %i[another_lisbon_parish another_municipality no_national_match unresolved_official_geography].sum { |key| row[key] }
        raise "Announcement accounting mismatch" unless row[:announcements] == row[:empty_licence] + row[:unrecognised_licence] + row[:identifiable_number] && row[:confirmed_rnal_match] <= row[:identifiable_number]
      end
      data
    end
  end
end
