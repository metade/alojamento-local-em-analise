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
      repeated = @dataset.candidates.select { |candidate| candidate["al_number"] }.group_by { |candidate| candidate["al_number"] }.values.select { |group| group.size > 1 }
      distances = distance_distribution(repeated)
      {
        "snapshot_name" => File.basename(@dataset.path),
        "source_dates" => @dataset.document.fetch("source_dates"),
        "summary" => city,
        "rnal" => @dataset.rnal,
        "listings" => @dataset.listings,
        "metrics" => city.fetch("metrics"),
        "districts" => districts,
        "unknown" => summary(nil),
        "candidates" => @dataset.candidates,
        "quotes" => JSON.parse(File.read(File.join(ROOT, "site_content", "quotes.json"))),
        "metadata" => {
          "source_urls" => {"airbnb" => Analysis::Data::AIRBNB_DATA_PAGE, "official" => Analysis::Data::OFFICIAL_URL}
        },
        "signals" => unidentified_licence_counts.merge(
          "repeated_listings" => listing_ids(repeated.flatten).size,
          "outside_listings" => regions.fetch("total")
        ),
        "distance_ranges" => distances.fetch("rows"),
        "distance_total" => repeated.size,
        "outside_regions" => regions
      }
    end

    private

    def listing_ids(candidates)
      candidates.flat_map { |c| c.fetch("listing_ids") }.uniq
    end

    def unidentified_licence_counts
      candidates = @dataset.candidates
      empty = listing_ids(candidates.select { |candidate| candidate["registration_status"] == "absent" })
      unrecognised = listing_ids(candidates.select { |candidate| candidate["registration_status"] == "unrecognised" })
      {
        "empty_licence_listings" => empty.size,
        "unrecognised_licence_listings" => unrecognised.size,
        "unidentified_licence_listings" => (empty | unrecognised).size
      }
    end

    def distance_distribution(groups)
      return {"rows" => []} if groups.empty?

      ranges = [[0.5, "Até 500 m"], [1, "500 m–1 km"], [2, "1–2 km"], [5, "2–5 km"], [Float::INFINITY, "Mais de 5 km"]]
      counts = Array.new(ranges.size + 1, 0)
      groups.each do |candidates|
        distances = candidates.map { |candidate| candidate.dig("official_match", "distance_km") }
        index = if distances.any?(&:nil?)
          ranges.size
        else
          ranges.index { |upper, _| distances.max <= upper }
        end
        counts[index] += 1
      end
      rows = ranges.each_with_index.map { |(_, label), index| {"label" => label, "count" => counts[index]} }
      rows << {"label" => "Distância por resolver", "count" => counts.last, "unresolved" => true} if counts.last > 0
      rows.each { |row| row["width"] = (row.fetch("count") * 100.0 / counts.max).round(1) }
      {"rows" => rows}
    end

    def outside_regions
      regions_by_listing = Hash.new { |hash, id| hash[id] = [] }
      @dataset.candidates.each do |candidate|
        record = candidate.fetch("official_match")
        next unless record

        municipality = Geography.municipality(record["municipality"])
        next unless municipality && municipality != "Lisboa"

        region = record["district"]&.strip
        region = nil if region.to_s.empty?
        candidate.fetch("listing_ids").each { |id| regions_by_listing[id] << region }
      end
      counts = regions_by_listing.values.each_with_object(Hash.new(0)) do |regions, totals|
        distinct = regions.uniq
        totals[distinct.size == 1 ? distinct.first : nil] += 1
      end
      maximum = counts.values.max
      rows = counts.sort_by { |name, count| [name.nil? ? 1 : 0, -count, name.to_s] }.map do |name, count|
        {"name" => name || "Região por resolver", "count" => count, "unresolved" => name.nil?, "width" => (count * 100.0 / maximum).round(1)}
      end
      {"rows" => rows, "total" => regions_by_listing.size}
    end

    def summary(parish = "Lisboa")
      candidates = @dataset.candidates.select { |c| parish == "Lisboa" || c["freguesia"] == parish }
      official = if parish == "Lisboa"
        @dataset.rnal.fetch("lisbon")
      else
        @dataset.rnal.fetch("parishes").find { |row| row["freguesia"] == parish }
      end
      original_listings = if parish == "Lisboa"
        @dataset.listings.fetch("lisbon")
      else
        @dataset.listings.fetch("parishes").find { |row| row["freguesia"] == parish }
      end
      numbered = candidates.count { |candidate| !candidate["al_number"].nil? }
      rnal_count = official.fetch("count")
      geometry = Overlap.geometry(rnal_count, candidates.size, numbered) if numbered <= rnal_count
      labels = geometry ? Overlap.labels(geometry, rnal_count - numbered, numbered, candidates.size - numbered) : []
      titles = {"rnal" => "Restante RNAL", "common" => "Com número AL", "airbnb" => "Sem número AL"}
      labels.each { |label| label["title"] = titles.fetch(label.fetch("key")) }
      metrics = {
        "geography" => parish || Geography::UNKNOWN,
        "rnal" => official.fetch("count"),
        "airbnb" => candidates.size,
        "geometry" => geometry,
        "overlap_labels" => labels,
        "intersection" => numbered,
        "airbnb_only" => candidates.size - numbered,
        "rnal_only" => rnal_count - numbered,
        "another_lisbon_parish" => nil,
        "another_municipality" => nil,
        "no_national_match" => nil,
        "unresolved_official_geography" => nil
      }
      {
        "candidate_count" => candidates.size,
        "listing_count" => original_listings.fetch("count"),
        "distinct_al_numbers" => candidates.filter_map { |c| c["al_number"] }.uniq.size,
        "official_numbers" => official.fetch("count"),
        "identifiable_listings" => nil,
        "metrics" => metrics,
        "categories" => nil
      }
    end
  end
end
