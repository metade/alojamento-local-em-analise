require "csv"
require "json"
require_relative "registration_metrics"
require_relative "overlap"

module AlojamentoLocal
  class SiteData
    ROOT = File.expand_path("../..", __dir__)
    SNAPSHOTS = File.join(ROOT, "data", "snapshots")
    SOURCE = File.join(ROOT, "site")
    SITE = File.join(ROOT, "_site")
    QUOTES = File.join(ROOT, "site_content", "quotes.json")
    DISTANCE_HISTORY = File.join(ROOT, "data", "history", "distance_ranges.csv")
    OUTSIDE_REGION_HISTORY = File.join(ROOT, "data", "history", "outside_regions.csv")
    PUBLIC_FILES = %w[metadata.json summary.json listings.csv licence_groups.csv freguesias.csv report.html].freeze
    DISTANCE_LABELS = {
      "500_m_1_km" => "500 m–1 km",
      "1_2_km" => "1–2 km",
      "2_5_km" => "2–5 km",
      "over_5_km" => "Mais de 5 km"
    }.freeze
    LABELS = {
      "localização observada não identificada" => "Localização observada não identificada",
      "número sem correspondência no RNAL" => "Número sem correspondência no RNAL",
      "geografia oficial não identificada" => "Geografia oficial não identificada",
      "sem licença" => "Sem licença",
      "sem licença identificável" => "Sem licença identificável",
      "licença repetida em várias localizações" => "Licença repetida em diferentes localizações",
      "licença oficial fora de Lisboa" => "Licença registada fora de Lisboa",
      "licença única em Lisboa" => "Licença única em Lisboa",
      "provável estabelecimento com anúncios múltiplos" => "Provável estabelecimento com anúncios múltiplos",
      "licença repetida na mesma localização" => "Licença repetida na mesma localização"
    }.freeze

    def initialize(snapshots: SNAPSHOTS, distance_history: DISTANCE_HISTORY, outside_region_history: OUTSIDE_REGION_HISTORY, quotes: QUOTES)
      @snapshots = snapshots
      @distance_history = distance_history
      @outside_region_history = outside_region_history
      @quotes = quotes
      @json_files = {}
    end

    def pretty(value)
      AlojamentoLocal::Geography.display_name(value)
    end

    def counts(rows)
      rows.each_with_object(Hash.new { |h, k| h[k] = {"listings" => 0, "licences" => 0, "estimate" => 0} }) do |row, out|
        value = out[row["classification"]]
        value["listings"] += row["listings"].to_i
        value["licences"] += row["identifiable_licences"].to_i
        value["estimate"] += row["establishments_estimate"].to_i
      end
    end

    def load_json(path)
      @json_files[path] ||= JSON.parse(File.read(path))
    end

    def public_runs
      Dir.children(@snapshots).filter_map do |name|
        path = File.join(@snapshots, name)
        path if File.directory?(path) && name.match?(/\A\d{4}-\d{2}-\d{2}__\d{4}-\d{2}-\d{2}\z/)
      end.sort_by do |path|
        metadata = load_json(File.join(path, "metadata.json"))
        [metadata.fetch("source_dates").fetch("airbnb_snapshot_date"), metadata.fetch("source_dates").fetch("official_register_download_date"), Gem::Version.new(metadata.fetch("methodology_version")), Gem::Version.new(metadata.fetch("analysis_version"))]
      end.reverse
    end

    def distance_ranges(run_id, summary)
      return [] unless File.file?(@distance_history)

      rows = CSV.read(@distance_history, headers: true).select { |row| row["run_id"] == run_id }
      return [] if rows.empty?

      keys = rows.map { |row| row["range"] }
      raise "Invalid distance ranges for #{run_id}" unless keys.sort == DISTANCE_LABELS.keys.sort &&
        rows.all? { |row| row["distance_method"] == "max_cross_cluster_pair_km_v1" && row["licence_groups"].to_s.match?(/\A\d+\z/) }

      counts = rows.to_h { |row| [row["range"], row["licence_groups"].to_i] }
      expected = summary.fetch("classifications").fetch("licença repetida em várias localizações", 0)
      raise "Distance range count differs from licence groups for #{run_id}" unless counts.values.sum == expected

      DISTANCE_LABELS.map { |key, label| {"key" => key, "label" => label, "count" => counts.fetch(key)} }
    end

    def outside_regions(run_id, listings)
      expected = listings.select { |row| row["classification"] == "licença oficial fora de Lisboa" }
        .sum { |row| row["listings"].to_i }
      return {"rows" => [], "total" => 0, "unresolved_municipality" => 0, "unresolved_region" => 0} if expected.zero?

      raise "Missing outside region counts for #{run_id}" unless File.file?(@outside_region_history)

      rows = CSV.read(@outside_region_history, headers: true).select { |row| row["run_id"] == run_id }
      keys = rows.map { |row| [row["resolution"], row["official_region"].to_s.strip] }
      unless rows.any? && keys.uniq.size == keys.size && rows.all? { |row|
        region = row["official_region"].to_s.strip
        resolution = row["resolution"]
        row["region_method"] == "official_register_nutsii_v1" && row["listings"].to_s.match?(/\A[1-9]\d*\z/) &&
          ((resolution == "resolved" && !region.empty?) || (%w[municipality_missing region_missing].include?(resolution) && region.empty?))
      }
        raise "Invalid outside region counts for #{run_id}"
      end

      counts = rows.to_h { |row| [[row["resolution"], row["official_region"].to_s.strip], row["listings"].to_i] }
      raise "Outside region count differs from listings for #{run_id}" unless counts.values.sum == expected

      unresolved_municipality = counts.delete(["municipality_missing", ""]).to_i
      unresolved_region = counts.delete(["region_missing", ""]).to_i
      chart = counts.sort_by { |(_, name), count| [-count, name] }.map { |(_, name), count| {"name" => name, "count" => count} }
      chart << {"name" => "Município não identificado", "count" => unresolved_municipality, "unresolved" => true} if unresolved_municipality.positive?
      chart << {"name" => "Região não identificada", "count" => unresolved_region, "unresolved" => true} if unresolved_region.positive?
      maximum = chart.map { |row| row["count"] }.max
      chart.each do |row|
        row["percent"] = (row["count"] * 100.0 / expected).round(1)
        row["width"] = (row["count"] * 100.0 / maximum).round(1)
      end
      {"rows" => chart, "total" => expected, "unresolved_municipality" => unresolved_municipality, "unresolved_region" => unresolved_region}
    end

    def measured_run(runs)
      runs.find do |path|
        metrics = File.join(path, "registration_metrics.json")
        next false unless File.file?(metrics)
        data = load_json(metrics)
        data["metric_version"] == AlojamentoLocal::RegistrationMetrics::VERSION &&
          data["methodology_version"] == AlojamentoLocal::RegistrationMetrics::SUPPORTED_METHODOLOGY_VERSION
      end || raise("No snapshot has supported measured registration metrics")
    end

    def site_data(runs)
      run_dir = measured_run(runs)
      run_id = File.basename(run_dir)
      summary = load_json(File.join(run_dir, "summary.json"))
      metadata = load_json(File.join(run_dir, "metadata.json"))
      listings = CSV.read(File.join(run_dir, "listings.csv"), headers: true).map(&:to_h)
      freguesias = CSV.read(File.join(run_dir, "freguesias.csv"), headers: true).map(&:to_h)
      grouped = listings.group_by { |row| row["freguesia"] }.transform_values { |rows| counts(rows) }
      ranges = distance_ranges(run_id, summary)
      regions = outside_regions(run_id, listings)
      metrics_path = File.join(run_dir, "registration_metrics.json")
      raise "Missing measured registration metrics for #{run_id}" unless File.file?(metrics_path)
      metrics_json = JSON.generate(load_json(metrics_path))
      AlojamentoLocal::RegistrationMetrics.validate!(JSON.parse(metrics_json, symbolize_names: true))
      metrics = JSON.parse(metrics_json)
      raise "Metric provenance differs" unless metrics["run_id"] == run_id && metrics["source_files"] == metadata["source_files"] && metrics["methodology_version"] == metadata["methodology_version"]
      measures = metrics.fetch("rows").to_h do |row|
        row["geometry"] = AlojamentoLocal::Overlap.geometry(row["rnal"], row["airbnb"], row["intersection"])
        row["unresolved"] = row["empty_licence"] + row["unrecognised_licence"]
        row["bubble_radius"] = row["announcements"].zero? ? 0 : (85*Math.sqrt(row["unresolved"].to_f/row["announcements"])).round(3)
        [row["geography"], row]
      end
      measures.fetch("Lisboa")["observed_unknown_parish"] = measures.fetch(AlojamentoLocal::Geography::UNKNOWN).fetch("announcements")
      measures.fetch("Lisboa")["official_unknown_parish"] = metrics.fetch("diagnostics").fetch("lisbon_entries_unresolved_parish")
      raise "City announcement count differs" unless summary.fetch("listings") == measures.fetch("Lisboa").fetch("announcements")
      districts = freguesias.reject { |row| row["freguesia"] == AlojamentoLocal::Geography::UNKNOWN }.map do |row|
        raw_name = row["freguesia"]
        measured = measures.fetch(raw_name)
        unless measured.fetch("announcements") == row.fetch("listings").to_i && measured.fetch("identifiable_number") == row.fetch("identifiable_licences").to_i
          raise "District announcement metrics differ: #{raw_name}"
        end
        # Keep the published routes while analysis now uses canonical parish names.
        route_name = AlojamentoLocal::Geography.route_name(raw_name)
        {
          "metrics" => measures.fetch(raw_name),
          "name" => raw_name,
          "display_name" => pretty(raw_name),
          "slug" => route_name.downcase.tr("áàâãäéêëíìîïóôõöúùûüç", "aaaaaeeeiiiioooouuuuc").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-$|\A\z/, ""),
          "listings" => row["listings"].to_i,
          # This snapshot field counts listing rows, not distinct registration numbers.
          "listings_with_identifiable_licence" => row["identifiable_licences"].to_i,
          "establishments_estimate" => row["establishments_estimate"].to_i,
          "categories" => LABELS.filter_map do |key, label|
            value = grouped.dig(raw_name, key)
            value && value["listings"].positive? ? {"key" => key, "label" => label, **value} : nil
          end
        }
      end

      {
        "run_id" => run_id,
        "newer_snapshot_without_metrics" => run_dir == runs.first ? nil : {
          "run_id" => File.basename(runs.first),
          "official_date" => load_json(File.join(runs.first, "metadata.json")).fetch("source_dates").fetch("official_register_download_date")
        },
        "metrics" => measures.fetch("Lisboa"),
        "summary" => summary,
        "metadata" => metadata,
        "official_count" => summary["official_registers_lisbon"],
        "listings" => listings,
        "repeated_listings" => listings.select { |row| row["classification"] == "licença repetida em várias localizações" }.sum { |row| row["listings"].to_i },
        "distance_ranges" => ranges,
        "distance_total" => ranges.sum { |range| range["count"] },
        "distance_max" => ranges.map { |range| range["count"] }.max.to_i,
        "outside_regions" => regions,
        "districts" => districts,
        "labels" => LABELS.values,
        "quotes" => File.exist?(@quotes) ? JSON.parse(File.read(@quotes)) : [],
        "runs" => runs.map { |path| File.basename(path) }
      }
    end
  end
end
