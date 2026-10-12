# frozen_string_literal: true

require "fileutils"
require "csv"
require "date"
require "json"
require "digest"
require "open3"
require "time"
require "tmpdir"

module AlojamentoLocal
  module Analysis
    module_function

    def validate_options!(mode:, force: false, reuse_existing: false)
      raise ArgumentError, "Mode must be public or local" unless %w[public local].include?(mode)
      raise ArgumentError, "Force is only supported in local mode" if force && mode != "local"
      raise ArgumentError, "Reuse is only supported in public mode" if reuse_existing && mode != "public"
    end

    def run_id_for(airbnb_path:, official_path:)
      airbnb_date = File.basename(airbnb_path)[/(\d{4}-\d{2}-\d{2})/, 1]
      official_date = File.basename(official_path)[/(\d{4}-\d{2}-\d{2})/, 1] || File.mtime(official_path).to_date.to_s
      "#{airbnb_date}__#{official_date}"
    end

    def existing_public_run(airbnb_path:, official_path:, output_root: "data/snapshots")
      run_id = run_id_for(airbnb_path: airbnb_path, official_path: official_path)
      path = File.join(output_root, run_id)
      return nil unless Dir.exist?(path)
      hashes = [airbnb_path, official_path].map { |source| Digest::SHA256.file(source).hexdigest }
      return nil unless public_run_current?(path, hashes)
      {run_id: run_id, path: path}
    end

    def public_run_current?(path, hashes)
      loader = PublicSnapshot::Loader.new
      metadata = loader.metadata(path)
      expected = {"airbnb" => hashes[0], "official" => hashes[1]}
      unless expected.all? { |key, hash| metadata.dig("source_files", key, "sha256") == hash }
        raise "Source hashes differ for existing dated snapshot: #{path}"
      end
      return false unless metadata["methodology_version"] == METHODOLOGY_VERSION && metadata["output_schema_version"] == OUTPUT_SCHEMA_VERSION &&
        metadata["analysis_version"] == ANALYSIS_VERSION && metadata["mode"] == "public" &&
        PublicSnapshot::REQUIRED_FILES.all? { |file| File.file?(File.join(path, file)) }
      loader.load(path)
      true
    end

    def run(airbnb_path:, official_path:, output_root: nil, history_path: nil, generate_pdf: false, mode: "local", force: false)
      validate_options!(mode: mode, force: force)

      output_root ||= mode == "public" ? "data/snapshots" : "data/private"
      history_path ||= mode == "public" ? "data/history/summary.csv" : "data/private/history/summary.csv"
      source_hashes = [airbnb_path, official_path].map { |path| Digest::SHA256.file(path).hexdigest }
      sources = PreparedSources::Pair.new(airbnb_path: airbnb_path, official_path: official_path)
      listings, official = classify(sources)
      raise "No observed Lisbon announcements" if listings.empty?
      dates = AlojamentoLocal.dates(listings)
      dates[:airbnb_snapshot_date] = File.basename(airbnb_path)[/(\d{4}-\d{2}-\d{2})/, 1] || dates[:airbnb_snapshot_date]
      official_download_date = File.basename(official_path)[/(\d{4}-\d{2}-\d{2})/, 1] || File.mtime(official_path).to_date.to_s
      dates[:official_register_download_date] = official_download_date
      base_run_id = "#{dates[:airbnb_snapshot_date]}__#{official_download_date}"
      run_id = base_run_id
      run_dir = File.join(output_root, run_id)
      public_run_current?(run_dir, source_hashes) if mode == "public" && Dir.exist?(run_dir)
      if mode == "local" && Dir.exist?(run_dir)
        raise "Run already exists and is immutable: #{run_dir}; use FORCE=1 for a preserved local rerun" unless force

        suffix = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
        run_id = "#{base_run_id}__rerun-#{suffix}"
        run_dir = File.join(output_root, run_id)
        increment = 2
        while Dir.exist?(run_dir)
          run_id = "#{base_run_id}__rerun-#{suffix}-#{increment}"
          run_dir = File.join(output_root, run_id)
          increment += 1
        end
      end

      groups = licence_groups(listings, official)
      freguesias = freguesia_rows(listings)
      public_listings = public_listing_rows(listings)
      public_groups = public_group_rows(groups)
      summary = summary(listings, groups, dates, run_id, mode, official: sources.official)
      summary[:historical_comparisons] = historical_comparisons(history_path, summary)
      metadata = metadata(airbnb_path, official_path, dates, run_id, mode)
      metrics = RegistrationMetrics.calculate(listings, sources.official)
      metrics[:run_id] = run_id
      metrics[:source_files] = metadata[:source_files]
      metrics[:methodology_version] = METHODOLOGY_VERSION
      metrics[:source_dates] = dates
      unless source_hashes == [airbnb_path, official_path].map { |path| Digest::SHA256.file(path).hexdigest }
        raise "Source bytes changed during analysis"
      end
      if mode == "local" && File.exist?(history_path) && CSV.foreach(history_path, headers: true).any? { |old| old["run_id"] == run_id }
        raise "History already exists for immutable local run #{run_id}"
      end
      destination = run_dir
      if mode == "public"
        FileUtils.mkdir_p(output_root)
        staging = Dir.mktmpdir(".analysis-", output_root)
        run_dir = File.join(staging, "snapshot")
      end
      begin
        FileUtils.mkdir_p(run_dir)
        write_outputs(run_dir: run_dir, mode: mode, listings: listings, groups: groups,
          freguesias: freguesias, public_listings: public_listings, public_groups: public_groups,
          metadata: metadata, summary: summary, metrics: metrics)
        generate_pdf_file(run_dir) if generate_pdf
        if mode == "public"
          validate_public_outputs!(run_dir)
          staged_histories = {}
          %w[summary.csv distance_ranges.csv outside_regions.csv].each do |filename|
            target = filename == "summary.csv" ? history_path : File.join(File.dirname(history_path), filename)
            staged_path = File.join(staging, filename)
            FileUtils.cp(target, staged_path) if File.file?(target)
            staged_histories[staged_path] = target
          end
          append_history(File.join(staging, "summary.csv"), summary, replace: true)
          append_distance_history(File.join(staging, "distance_ranges.csv"), run_id, listings, replace: true)
          append_outside_region_history(File.join(staging, "outside_regions.csv"), run_id, listings, replace: true)
          publish_public_run!(run_dir, destination, staged_histories, staging)
        else
          append_history(history_path, summary)
        end
        {run_id: run_id, path: destination, summary: summary}
      ensure
        FileUtils.rm_rf(staging) if staging
      end
    end

    # Presentation receives already calculated aggregates; publication remains
    # staged and validated by run after all output files have been written.
    def write_outputs(run_dir:, mode:, listings:, groups:, freguesias:, public_listings:, public_groups:, metadata:, summary:, metrics:)
      if mode == "public"
        inputs = JSON.parse(JSON.generate({metadata: metadata, summary: summary, groups: public_groups,
          announcements: public_listings, parishes: freguesias, metrics: metrics}))
        snapshot = PublicSnapshot.from_legacy(**inputs.transform_keys(&:to_sym))
        PublicSnapshot::Validator.new.validate!(snapshot, expected_run_id: metadata.fetch(:run_id), schema: PublicSnapshot::SCHEMA_VERSION)
        File.write(File.join(run_dir, PublicSnapshot::FILE), JSON.pretty_generate(snapshot.to_h) + "\n")
        report_filename = "report.html"
      else
        File.write(File.join(run_dir, "registration_metrics.json"), JSON.pretty_generate(metrics) + "\n")
        write_csv(File.join(run_dir, "listings_detailed.csv"), detailed_listing_rows(listings))
        write_csv(File.join(run_dir, "licence_groups_detailed.csv"), detailed_group_rows(groups))
        write_csv(File.join(run_dir, "freguesias_summary.csv"), freguesias)
        write_json_outputs(run_dir, metadata, summary, "metadata_local.json", "summary_local.json")
        report_filename = "report_local.html"
      end
      arguments = mode == "public" ? snapshot.report_arguments : [metadata, summary, public_groups, public_listings, metrics]
      File.write(File.join(run_dir, report_filename), Report.complete_html(*arguments))
    end

    # Validate the full result first, then replace the dated snapshot and its
    # history rows together. Roll back the previous files if installation fails.
    def publish_public_run!(staged_run, destination, histories, staging)
      installed = []
      {staged_run => destination, **histories}.each_with_index do |(source, target), index|
        FileUtils.mkdir_p(File.dirname(target))
        backup = File.join(staging, "previous-#{index}")
        existed = File.exist?(target)
        FileUtils.mv(target, backup) if existed
        installed << [target, existed ? backup : nil]
        FileUtils.mv(source, target)
      end
    rescue Exception
      installed.reverse_each do |target, backup|
        FileUtils.rm_rf(target)
        FileUtils.mv(backup, target) if backup && File.exist?(backup)
      end
      raise
    end

    def analyse(airbnb_path, official_path)
      classify(PreparedSources::Pair.new(airbnb_path: airbnb_path, official_path: official_path))
    end

    def classify(sources)
      official = sources.official.classification_lookup
      counts = sources.airbnb.licence_counts
      data = sources.airbnb.entries.map do |entry|
        row = entry.raw
        license = entry.number
        record = official[license]
        distance = if record && record["LatLong"] && !record["LatLong"].empty? && AlojamentoLocal.coordinates_for({lat: row["latitude"], lng: row["longitude"]})
          official_lat, official_lng = AlojamentoLocal.parse_lat_long(record["LatLong"])
          Haversine.distance(official_lat, official_lng, row["latitude"].to_f, row["longitude"].to_f).to_km
        end
        {
          fonte: "airbnb", licensa: license, licensa_raw: row["license"], license_status: status(record, distance, counts[license]),
          url: row["listing_url"], bairro: entry.parish, nome: row["name"], lat: row["latitude"], lng: row["longitude"],
          room_type: row["room_type"], property_type: row["property_type"], quartos: row["bedrooms"], host_id: row["host_id"],
          airbnb_date: parse_date(row["last_scraped"]), official_date: record && parse_date(record["DataRegisto"]),
          official_name: record && record["Denominacao"], official_address: record && record["Endereco"], official_concelho: record && record["Concelho"], official_region: record && record["NUTSII"],
          official_modalidade: record && record["Modalidade"], official_capacity: record && record["NrUtentes"], distance_km: distance
        }
      end
      data.group_by { |row| row[:licensa] }.each do |license, members|
        next if license.to_s.empty?
        cluster_count = AlojamentoLocal.spatial_clusters(members).size
        assessment = AlojamentoLocal.license_group_assessment(members, official[license])
        members.each { |row| row[:spatial_cluster_count] = cluster_count; row[:license_group_assessment] = assessment }
      end
      data.each do |row|
        row[:spatial_cluster_count] ||= 1
        row[:license_group_assessment] ||= AlojamentoLocal.missing_license_assessment(row[:licensa_raw])
      end
      [data, official]
    end

    def parse_date(value); value && !value.empty? ? Date.parse(value) : nil; rescue ArgumentError; nil end
    def status(record, distance, count)
      return "sem licença identificável" unless record
      values = []
      values << "licença fora da localização (distancia #{distance})" if distance && distance > 1
      values << "licença reutilizada #{count}" if count > 1
      values.join(";")
    end
    def licence_groups(listings, official)
      listings.group_by { |row| [row[:licensa].to_s, row[:license_group_assessment].to_s] }.map do |(license, _assessment), rows|
        {licensa: license, licence_raw_examples: rows.map { |r| r[:licensa_raw] }.compact.uniq.join(" | "), listings: rows.size,
         spatial_locations: license.empty? ? 0 : rows.first[:spatial_cluster_count], classification: rows.first[:license_group_assessment],
         official_name: rows.first[:official_name], official_concelho: rows.first[:official_concelho], official_modalidade: rows.first[:official_modalidade],
         establishment_estimate: AlojamentoLocal.establishment_estimate(rows)}
      end.sort_by { |row| row[:licensa] }
    end

    def public_listing_rows(listings)
      listings.group_by { |row| [row[:bairro].to_s, row[:license_group_assessment].to_s] }.map do |(freguesia, classification), rows|
        {
          freguesia: freguesia,
          classification: classification,
          listings: rows.size,
          identifiable_licences: AnnouncementCounts.calculate(rows)[:identifiable_number],
          establishments_estimate: AlojamentoLocal.establishment_estimate(rows)
        }
      end.sort_by { |row| [row[:freguesia], row[:classification]] }
    end

    def public_group_rows(groups)
      groups.group_by do |group|
        [group[:classification].to_s, public_municipality(group[:official_concelho]), public_type(group[:official_modalidade])]
      end.map do |(classification, municipality, type), rows|
        {
          classification: classification,
          official_municipality: municipality,
          official_type: type,
          licence_groups: rows.count { |row| !row[:licensa].to_s.empty? },
          listings: rows.sum { |row| row[:listings].to_i },
          spatial_locations: rows.sum { |row| row[:spatial_locations].to_i },
          establishments_estimate: rows.sum { |row| row[:establishment_estimate].to_i }
        }
      end.sort_by { |row| [row[:classification], row[:official_municipality], row[:official_type]] }
    end

    def detailed_listing_rows(listings)
      headers = %i[fonte licensa licensa_raw license_status url bairro nome lat lng room_type property_type quartos host_id airbnb_date official_date official_name official_address official_concelho official_modalidade official_capacity distance_km spatial_cluster_count license_group_assessment]
      listings.map { |listing| headers.to_h { |header| [header, listing[header]] } }
    end

    def detailed_group_rows(groups)
      groups.map do |group|
        group.slice(:licensa, :licence_raw_examples, :listings, :spatial_locations, :classification,
                    :official_name, :official_concelho, :official_modalidade, :establishment_estimate)
      end
    end

    def public_municipality(value)
      return "não identificado" if value.to_s.empty?
      value == "Lisboa" ? "Lisboa" : "outro município"
    end

    def public_type(value)
      text = value.to_s
      return "não identificado" if text.empty?
      return "hospedagem" if text.match?(/Hospedagem|Hostel|Quartos/i)
      return "apartamento" if text.match?(/Apartamento|Moradia|Casa/i)

      "outro tipo"
    end

    def validate_public_outputs!(run_dir)
      loader = PublicSnapshot::Loader.new
      loader.load(run_dir, expected_run_id: loader.metadata(run_dir).fetch("run_id"))
    end
    def freguesia_rows(listings)
      grouped = listings.group_by { |row| row[:bairro].to_s }
      Geography::PARISHES.each { |name| grouped[name] ||= [] }
      grouped.map { |name, rows| {freguesia: name, listings: rows.size, identifiable_licences: AnnouncementCounts.calculate(rows)[:identifiable_number], establishments_estimate: AlojamentoLocal.establishment_estimate(rows)} }.sort_by { |r| r[:freguesia] }
    end
    def summary(listings, groups, dates, run_id, mode, official: {})
      counts = groups.reject { |g| g[:licensa].to_s.empty? }.group_by { |g| g[:classification] }.transform_values(&:size)
      {run_id: run_id, source_dates: dates, methodology_version: METHODOLOGY_VERSION, listings: listings.size, licence_groups: groups.count { |g| !g[:licensa].to_s.empty? },
       official_registers_lisbon: official.is_a?(PreparedSources::Official) ? official.lisbon_entries.size : official.values.count { |record| record["Concelho"] == "Lisboa" },
       establishment_estimate: AlojamentoLocal.establishment_estimate(listings), classifications: counts, mode: mode, generated_at: Time.now.utc.iso8601}
    end
    def metadata(airbnb, official, dates, run_id, mode)
      commit, = Open3.capture2("git", "rev-parse", "HEAD")
      changes, = Open3.capture2("git", "status", "--porcelain", "--untracked-files=no")
      {run_id: run_id, source_urls: {airbnb: Data.airbnb_url(dates[:airbnb_snapshot_date]), official: Data::OFFICIAL_URL}, source_dates: dates,
       source_files: {airbnb: {sha256: Digest::SHA256.file(airbnb).hexdigest}, official: {sha256: Digest::SHA256.file(official).hexdigest}},
       git_commit: commit.strip, git_worktree_dirty: !changes.empty?, analysis_version: ANALYSIS_VERSION, methodology_version: METHODOLOGY_VERSION, output_schema_version: OUTPUT_SCHEMA_VERSION,
       mode: mode}
    end
    def write_json_outputs(run_dir, metadata, summary, metadata_filename, summary_filename)
      File.write(File.join(run_dir, metadata_filename), JSON.pretty_generate(metadata) + "\n")
      File.write(File.join(run_dir, summary_filename), JSON.pretty_generate(summary) + "\n")
    end
    def write_csv(path, rows)
      headers = rows.empty? ? PUBLIC_CSV_SCHEMAS.fetch(File.basename(path), []) : rows.first.keys
      CSV.open(path, "w", write_headers: true, headers: headers) { |csv| rows.each { |row| csv << headers.map { |h| row[h] } } }
    end
    def append_history(path, row, replace: false)
      headers = %w[run_id source_airbnb_date source_official_register_download_date methodology_version listings licence_groups establishment_estimate generated_at]
      values = {"source_airbnb_date" => row[:source_dates][:airbnb_snapshot_date], "source_official_register_download_date" => row[:source_dates][:official_register_download_date]}
      fields = headers.map { |key| row[key.to_sym] || values[key] }
      write_history_rows(path, headers, row[:run_id], [fields], replace: replace)
    end

    # Preserve other date pairs byte for byte; each public run has one current
    # summary and one current set of auxiliary rows. Git retains earlier results.
    def write_history_rows(path, headers, run_id, rows, replace: false)
      existing = File.file?(path) && !File.empty?(path) ? File.read(path) : CSV.generate_line(headers)
      parser = CSV.new(existing, headers: true)
      kept = []
      parser.each do |row|
        if row["run_id"] == run_id
          raise "History already exists for run #{run_id}" unless replace
        else
          kept << parser.line
        end
      end
      raise "Invalid history schema: #{path}" unless parser.headers == headers
      header = existing.lines.first
      output = header + kept.join + rows.map { |row| CSV.generate_line(row) }.join
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, output)
    end

    def distance_range_counts(listings)
      counts = DISTANCE_RANGE_KEYS.to_h { |key| [key, 0] }
      listings.select { |row| row[:license_group_assessment] == "licença repetida em várias localizações" && AlojamentoLocal.coordinates_for(row) }
        .group_by { |row| row[:licensa] }.each_value do |rows|
          distance = AlojamentoLocal.max_cross_cluster_distance_km(rows)
          counts[AlojamentoLocal.distance_range_key(distance)] += 1
        end
      counts
    end

    def append_distance_history(path, run_id, listings, replace: false)
      headers = %w[run_id distance_method range licence_groups]
      counts = distance_range_counts(listings)
      rows = DISTANCE_RANGE_KEYS.map { |range| [run_id, "max_cross_cluster_pair_km_v1", range, counts.fetch(range)] }
      write_history_rows(path, headers, run_id, rows, replace: replace)
    end

    def outside_region_counts(listings)
      listings.each_with_object(Hash.new(0)) do |row, counts|
        next unless row[:license_group_assessment] == "licença oficial fora de Lisboa"

        municipality = row[:official_concelho].to_s.strip
        region = row[:official_region].to_s.strip
        key = if municipality.empty?
          ["municipality_missing", ""]
        elsif region.empty?
          ["region_missing", ""]
        else
          ["resolved", region]
        end
        counts[key] += 1
      end
    end

    def append_outside_region_history(path, run_id, listings, replace: false)
      headers = %w[run_id region_method resolution official_region listings]
      rows = outside_region_counts(listings).sort_by { |(resolution, region), _| [resolution, region] }.map do |(resolution, region), count|
        [run_id, "official_register_nutsii_v1", resolution, region, count]
      end
      write_history_rows(path, headers, run_id, rows, replace: replace)
    end

    def historical_comparisons(path, current)
      return [] unless File.exist?(path)
      CSV.foreach(path, headers: true).reject { |old| old["run_id"] == current[:run_id] }.map do |old|
        compatible = old["methodology_version"] == current[:methodology_version]
        {run_id: old["run_id"], status: compatible ? "comparável" : "incompatível — metodologia diferente",
         metrics: compatible ? {listings: old["listings"].to_i, licence_groups: old["licence_groups"].to_i, establishment_estimate: old["establishment_estimate"].to_i} : {}}
      end
    end
    def generate_pdf_file(run_dir)
      html = File.join(run_dir, "report.html"); pdf = File.join(run_dir, "report.pdf")
      system("wkhtmltopdf", "--quiet", html, pdf) || system("weasyprint", html, pdf)
    end
  end
end
