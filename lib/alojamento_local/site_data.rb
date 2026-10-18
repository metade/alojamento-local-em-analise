require "json"

module AlojamentoLocal
  # Derives presentation values from the candidate snapshot. Templates retain
  # the established site layout; unavailable measures remain nil.
  class SiteData
    ROOT = File.expand_path("../..", __dir__)
    SOURCE = File.join(ROOT, "site")

    def initialize(dataset:)
      @dataset = dataset
    end

    def site_data
      districts = Geography::PARISHES.map do |parish|
        route = Geography.route_name(parish)
        slug = Geography.key(route).gsub(/[^a-z0-9]+/, "-")
        summary(parish).merge("name" => parish, "display_name" => parish, "slug" => slug)
      end
      city = summary
      regions = outside_regions
      distances = distance_distribution
      candidates = report_candidates
      {
        "snapshot_name" => File.basename(@dataset.path),
        "summary_download" => @dataset.download_paths.first,
        "candidates_download" => @dataset.download_paths.last,
        "source_dates" => @dataset.summary_document.fetch("source_dates"),
        "summary" => city,
        "metrics" => city.fetch("metrics"),
        "districts" => districts,
        "unknown" => summary(nil),
        "candidates" => candidates,
        "report_candidates" => candidates.reject { |candidate| unflagged_match?(candidate) },
        "quotes" => JSON.parse(File.read(File.join(ROOT, "site_content", "quotes.json"))),
        "metadata" => {
          "source_urls" => {"airbnb" => Analysis::Data::AIRBNB_DATA_PAGE, "official" => Analysis::Data::OFFICIAL_URL}
        },
        "signals" => @dataset.summary_document.fetch("signals"),
        "distance_ranges" => distances.fetch("rows"),
        "distance_total" => @dataset.summary_document.fetch("repeated_number_distances").sum { |row| row["count"] },
        "outside_regions" => regions
      }
    end

    private

    def report_candidates
      candidates = @dataset.candidates.map do |candidate|
        candidate.merge("grouping_review_count" => 0, "minimum_merge_score" => nil)
      end
      by_listing = Hash.new { |hash, id| hash[id] = [] }
      candidates.each { |candidate| candidate["listing_ids"].each { |id| by_listing[id] << candidate } }
      @dataset.grouping_assessments.each do |pair|
        related = pair["listing_ids"].flat_map { |id| by_listing.fetch(id) }.uniq
        related.each do |candidate|
          if pair["outcome"] == "review"
            candidate["grouping_review_count"] += 1
          elsif pair["outcome"] == "merge"
            candidate["minimum_merge_score"] = [candidate["minimum_merge_score"], pair["score"]].compact.min
          end
        end
      end
      candidates
    end

    def unflagged_match?(candidate)
      return false unless candidate["registration_status"] == "found" && candidate["signals"].empty? && candidate["grouping_review_count"].zero?

      record = candidate.fetch("official_match")
      parish = candidate["freguesia"]
      distance = record["distance_km"]
      parish && candidate.dig("geography", "coordinate_freguesia") == parish &&
        record["municipality"] == "Lisboa" && record["freguesia"] == parish &&
        !distance.nil? && distance <= 0.5
    end

    def distance_distribution
      counts = @dataset.summary_document.fetch("repeated_number_distances")
      return {"rows" => []} if counts.sum { |row| row["count"] }.zero?
      labels = ["Até 500 m", "500 m–1 km", "1–2 km", "2–5 km", "Mais de 5 km", "Distância por resolver"]
      maximum = counts.map { |row| row["count"] }.max
      rows = counts.each_with_index.filter_map do |row, index|
        next if index == 5 && row["count"].zero?
        value = {"label" => labels[index], "count" => row["count"], "width" => (row["count"] * 100.0 / maximum).round(1)}
        value["unresolved"] = true if index == 5
        value
      end
      {"rows" => rows}
    end

    def outside_regions
      counts = @dataset.summary_document.fetch("outside_regions")
      maximum = counts.map { |row| row["count"] }.max
      rows = counts.map do |row|
        {"name" => row["district"] || "Região por resolver", "count" => row["count"], "unresolved" => row["district"].nil?,
         "width" => (row["count"] * 100.0 / maximum).round(1)}
      end
      {"rows" => rows, "total" => @dataset.summary_document.dig("signals", "outside_listings")}
    end

    def summary(parish = "Lisboa")
      scope = if parish == "Lisboa"
        @dataset.summary_document.fetch("lisbon")
      else
        @dataset.summary_document.fetch("parishes").find { |row| row["freguesia"] == parish }
      end
      candidate_count = scope.fetch("candidates_count")
      numbered = scope.fetch("numbered_candidates_count")
      declared = scope.fetch("distinct_al_numbers_count")
      matched = scope.fetch("matched_al_numbers_count")
      rnal_count = scope.fetch("official_count")
      geometry = Overlap.geometry(rnal_count, candidate_count, matched)
      labels = Overlap.labels(geometry, rnal_count - matched, matched, candidate_count - matched)
      titles = {"rnal" => "Apenas no RNAL", "common" => "Correspondência encontrada", "airbnb" => "Outros potenciais AL"}
      labels.each { |label| label["title"] = titles.fetch(label.fetch("key")) }
      counts = {"matched" => matched, "repeated" => numbered - declared,
                "outside" => declared - matched, "unrecognised" => scope.fetch("unrecognised_licence_candidates_count"),
                "mixed" => scope.fetch("mixed_licence_candidates_count"), "exempt" => scope.fetch("exempt_candidates_count"), "absent" => scope.fetch("empty_licence_candidates_count")}
      category_labels = {"matched" => "Número no RNAL (uma vez)", "repeated" => "Ocorrências adicionais de números reutilizados",
                         "outside" => "Número fora do RNAL desta geografia", "unrecognised" => "Declaração não reconhecida",
                         "mixed" => "Declarações mistas sem número", "exempt" => "Isenção declarada — por verificar", "absent" => "Sem número declarado"}
      breakdown = counts.map do |key, count|
        {"key" => key, "label" => category_labels.fetch(key), "count" => count,
         "width" => candidate_count.zero? ? 0 : count * 100.0 / candidate_count}
      end
      metrics = {
        "geography" => parish || Geography::UNKNOWN,
        "rnal" => rnal_count,
        "airbnb" => candidate_count,
        "geometry" => geometry,
        "overlap_labels" => labels,
        "candidate_breakdown" => breakdown,
        "remaining_candidates" => candidate_count - matched,
        "matched_al_numbers" => matched,
        "other_declared_numbers" => declared - matched,
        "unmatched_official_numbers" => rnal_count - matched,
        "declared_numbers" => declared,
        "candidate_count" => candidate_count,
        "unnumbered_candidates" => candidate_count - numbered,
        "another_lisbon_parish" => nil,
        "another_municipality" => nil,
        "no_national_match" => nil,
        "unresolved_official_geography" => nil
      }
      {
        "candidate_count" => candidate_count,
        "listing_count" => scope.fetch("listings_count"),
        "distinct_al_numbers" => scope.fetch("distinct_al_numbers_count"),
        "official_numbers" => rnal_count,
        "identifiable_listings" => nil,
        "metrics" => metrics,
        "categories" => nil
      }
    end
  end
end
