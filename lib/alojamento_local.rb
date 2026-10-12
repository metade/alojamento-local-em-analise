require_relative "alojamento_local/public_schema"
require_relative "alojamento_local/data"
require "fileutils"
require "haversine"
require "csv"
require "date"
require "json"
require "set"
require "digest"
require "open3"
require "erb"
require "time"
require "tmpdir"

module AlojamentoLocal
  ANALYSIS_VERSION = "3.2.0"
  OUTPUT_SCHEMA_VERSION = "4.0.0"
  METHODOLOGY_VERSION = "2.1.0"
  COLLAPSIBLE_ASSESSMENTS = [
    "provável estabelecimento com anúncios múltiplos",
    "licença repetida na mesma localização"
  ].freeze
  DISTANCE_RANGE_KEYS = %w[500_m_1_km 1_2_km 2_5_km over_5_km].freeze

  module CLI
    module_function

    def mode!(arguments)
      mode = "local"
      remaining = arguments.dup

      while (argument = remaining.shift)
        case argument
        when "--mode"
          mode = remaining.shift
        when /\A--mode=(.+)\z/
          mode = Regexp.last_match(1)
        when "--force"
          # Parsed separately by force?; accept it here so option validation succeeds.
        when "--reuse-existing"
          # Parsed separately by reuse_existing?; accept it here so option validation succeeds.
        when "-h", "--help"
          puts "Usage: bundle exec ruby run_me.rb [--mode public|local] [--force] [--reuse-existing]"
          exit 0
        else
          raise ArgumentError, "Unknown option: #{argument}"
        end
      end

      raise ArgumentError, "Mode must be public or local" unless %w[public local].include?(mode)

      mode
    end

    def force?(arguments)
      arguments.include?("--force")
    end

    def reuse_existing?(arguments)
      arguments.include?("--reuse-existing")
    end
  end

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
    PreparedSources::Official.new(source_path).classification_lookup
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

  module Analysis
    module_function

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
      metadata = JSON.parse(File.read(File.join(path, "metadata.json")))
      expected = {"airbnb" => hashes[0], "official" => hashes[1]}
      unless expected.all? { |key, hash| metadata.dig("source_files", key, "sha256") == hash }
        raise "Source hashes differ for existing dated snapshot: #{path}"
      end
      metadata["methodology_version"] == METHODOLOGY_VERSION && metadata["output_schema_version"] == OUTPUT_SCHEMA_VERSION &&
        metadata["analysis_version"] == ANALYSIS_VERSION && metadata["mode"] == "public" &&
        (PUBLIC_CSV_SCHEMAS.keys + %w[summary.json report.html registration_metrics.json]).all? { |file| File.file?(File.join(path, file)) }
    end

    def run(airbnb_path:, official_path:, output_root: nil, history_path: nil, generate_pdf: false, mode: "local", force: false)
      raise ArgumentError, "Mode must be public or local" unless %w[public local].include?(mode)
      raise ArgumentError, "--force is only supported in local mode" if force && mode == "public"

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
        raise "Run already exists and is immutable: #{run_dir}; use --force for a preserved local rerun" unless force

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
      File.write(File.join(run_dir, "registration_metrics.json"), JSON.pretty_generate(metrics) + "\n")
      if mode == "public"
        write_csv(File.join(run_dir, "listings.csv"), public_listings)
        write_csv(File.join(run_dir, "licence_groups.csv"), public_groups)
        write_csv(File.join(run_dir, "freguesias.csv"), freguesias)
        write_json_outputs(run_dir, metadata, summary, "metadata.json", "summary.json")
        report_filename = "report.html"
      else
        write_csv(File.join(run_dir, "listings_detailed.csv"), detailed_listing_rows(listings))
        write_csv(File.join(run_dir, "licence_groups_detailed.csv"), detailed_group_rows(groups))
        write_csv(File.join(run_dir, "freguesias_summary.csv"), freguesias)
        write_json_outputs(run_dir, metadata, summary, "metadata_local.json", "summary_local.json")
        report_filename = "report_local.html"
      end
      File.write(File.join(run_dir, report_filename), Report.complete_html(metadata, summary, public_groups, public_listings, metrics))
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

  module Report
    module_function

    def complete_html(metadata, summary, groups, freguesias, metrics)
      html(metadata, summary, groups, freguesias).sub("</body></html>", metrics_section(metrics) + historical_section(summary) + "</body></html>")
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

    def metrics_section(metrics)
      safe = ->(value) { ERB::Util.html_escape(value.to_s) }
      headers = RegistrationMetrics::COUNTS
      rows = metrics[:rows].map { |row| "<tr><th>#{safe.call(row[:geography])}</th>#{headers.map { |key| "<td>#{row[key.to_sym]}</td>" }.join}</tr>" }.join
      definitions = metrics[:definitions].map { |key, value| "<dt>#{safe.call(key)}</dt><dd>#{safe.call(value)}</dd>" }.join
      "<section><h2>Números distintos e anúncios</h2><p>Métricas #{safe.call(metrics[:metric_version])}; unidades e definições em registration_metrics.json.</p><table><thead><tr><th>Geografia</th>#{headers.map { |key| "<th>#{safe.call(key)}</th>" }.join}</tr></thead><tbody>#{rows}</tbody></table><dl>#{definitions}</dl></section>"
    end

    def historical_section(summary)
      rows = summary[:historical_comparisons].map do |item|
        metrics = item[:metrics]
        "<tr><td>#{ERB::Util.html_escape(item[:run_id].to_s)}</td><td>#{ERB::Util.html_escape(item[:status].to_s)}</td><td>#{metrics[:listings] || '—'}</td><td>#{metrics[:licence_groups] || '—'}</td></tr>"
      end.join
      "<section><h2>Comparação histórica</h2><table><thead><tr><th>Run</th><th>Estado</th><th>Listagens</th><th>Grupos de licença</th></tr></thead><tbody>#{rows.empty? ? '<tr><td colspan=\"4\">Sem runs anteriores.</td></tr>' : rows}</tbody></table><p>Comparações incompatíveis são identificadas quando a versão da metodologia muda.</p></section>"
    end

    def html(metadata, summary, groups, freguesias)
      safe = ->(value) { ERB::Util.html_escape(value.to_s) }
      labels = summary[:classifications]
      rows = groups.map { |g| "<tr><td>#{safe.call(g[:classification])}</td><td>#{safe.call(g[:official_municipality])}</td><td>#{safe.call(g[:official_type])}</td><td>#{g[:licence_groups]}</td><td>#{g[:listings]}</td><td>#{g[:spatial_locations]}</td></tr>" }.join
      freg = freguesias.map { |r| "<tr><td>#{safe.call(r[:freguesia])}</td><td>#{safe.call(r[:classification])}</td><td>#{r[:listings]}</td><td>#{r[:identifiable_licences]}</td><td>#{r[:establishments_estimate]}</td></tr>" }.join
      examples = illustrative_anomalies.map do |example|
        "<tr><th scope='row'>#{safe.call(example[:signal])}</th><td>#{safe.call(example[:pattern])}</td><td>#{safe.call(example[:reading])}</td></tr>"
      end.join
      "<!doctype html><html lang='pt'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Alojamento Local em Lisboa — #{safe.call(summary[:run_id])}</title><style>body{font:16px system-ui;max-width:1200px;margin:auto;padding:1rem;color:#243447}header{background:#123;padding:1.5rem;color:white;border-radius:12px}section{margin:1.5rem 0}table{border-collapse:collapse;width:100%;display:block;overflow:auto}th,td{padding:.5rem;border-bottom:1px solid #ddd;text-align:left;vertical-align:top}th{background:#edf2f7}.cards{display:flex;flex-wrap:wrap;gap:1rem}.card{padding:1rem;background:#edf2f7;border-radius:10px;min-width:145px}.bar{background:#2878c8;color:white;padding:.35rem;margin:.3rem 0;border-radius:4px}@media print{body{font-size:11px}header{print-color-adjust:exact}.no-print{display:none}}@media(max-width:600px){.cards{display:grid;grid-template-columns:1fr 1fr}}</style><body><header><h1>Alojamento Local em Lisboa</h1><p>Run #{safe.call(summary[:run_id])} · modo #{safe.call(summary[:mode])} · gerado em #{safe.call(summary[:generated_at])}</p><p>Indicador para verificação oficial</p></header><section><h2>Resumo</h2><div class='cards'><div class='card'><b>#{summary[:listings]}</b><br>listagens</div><div class='card'><b>#{summary[:licence_groups]}</b><br>grupos de licença</div><div class='card'><b>#{summary[:establishment_estimate]}</b><br>estimativa de estabelecimentos</div></div>#{labels.map { |label,count| "<div class='bar' style='width:#{[count * 100 / [summary[:licence_groups],1].max,100].min}%'>#{safe.call(label)}: #{count}</div>" }.join}</section><section><h2>Grupos de licenças (agregado)</h2><table><thead><tr><th>Classificação</th><th>Concelho oficial</th><th>Tipo oficial</th><th>Grupos</th><th>Listagens</th><th>Localizações</th></tr></thead><tbody>#{rows}</tbody></table></section><section><h2>Por freguesia e classificação</h2><table><thead><tr><th>Freguesia</th><th>Classificação</th><th>Listagens</th><th>Licenças identificáveis</th><th>Estimativa</th></tr></thead><tbody>#{freg}</tbody></table></section><section><h2>Exemplos ilustrativos</h2><p>Os exemplos seguintes são sintéticos e servem apenas para explicar os sinais. Não correspondem a anúncios, operadores, números de licença, endereços ou casos individuais.</p><table><thead><tr><th>Sinal</th><th>Padrão ilustrativo</th><th>Leitura prudente</th></tr></thead><tbody>#{examples}</tbody></table></section><section><h2>Proveniência e método</h2><p>Fontes: <a href='#{safe.call(metadata[:source_urls][:airbnb])}'>Airbnb</a> e <a href='#{safe.call(metadata[:source_urls][:official])}'>registo oficial</a>. Datas e hashes SHA-256 estão em <code>metadata.json</code>. Metodologia #{safe.call(metadata[:methodology_version])}; análise #{safe.call(metadata[:analysis_version])}.</p><p>As classificações são indicadores analíticos e não conclusões legais. Requerem verificação junto das fontes oficiais.</p></section></body></html>"
    end
  end
end

require_relative "alojamento_local/registration_metrics"

require_relative "alojamento_local/public_snapshot"
