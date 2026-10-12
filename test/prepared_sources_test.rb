require "minitest/autorun"
require "tmpdir"
require_relative "../lib/alojamento_local"
require_relative "../lib/alojamento_local/site_data"
require_relative "support/legacy_snapshot"

class PreparedSourcesTest < Minitest::Test
  def with_method(object, name, replacement)
    original = object.method(name)
    object.define_singleton_method(name, replacement)
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  def with_sources
    Dir.mktmpdir do |dir|
      official = File.join(dir, "official-2026-09-26.csv")
      CSV.open(official, "w", write_headers: true, headers: %w[NrRNAL Concelho Freguesia LatLong Denominacao]) do |csv|
        csv << ["001", " Lisboa ", "ARROIOS", "38.71;-9.14", "First"]
        csv << ["1", "Lisboa", "Arroios", "38.71;-9.14", "Second"]
        csv << ["2", "Lisboa", "Arroios", "38.71;-9.14", "Lisbon"]
        csv << ["2", "Porto", "Bonfim", "41;-8", "Porto"]
        csv << ["3", "Lisboa", "Arroios", "38.71;-9.14", "First parish"]
        csv << ["3", "Lisboa", "Belém", "38.71;-9.14", "Other parish"]
        csv << ["4", "Lisboa", "Arroios", "38.71;-9.14", "First coordinates"]
        csv << ["4", "Lisboa", "Arroios", "38.72;-9.14", "Other coordinates"]
        csv << ["n/a", "Lisboa", nil, nil, "Unparseable"]
        csv << ["5", nil, nil, nil, "Missing municipality"]
      end
      airbnb = File.join(dir, "listings-2026-06-23.csv")
      CSV.open(airbnb, "w", write_headers: true, headers: %w[neighbourhood_group_cleansed license neighbourhood_cleansed latitude longitude last_scraped]) do |csv|
        csv << ["Lisboa", "001/AL", "Arroios", "38.71", "-9.14", "2026-06-23"]
        csv << [" Lisboa ", "1", "Arroios", "38.71", "-9.14", "2026-06-23"]
        csv << ["lisboa", "1", "Arroios", "38.71", "-9.14", "2026-06-23"]
        csv << ["Porto", "1", "Arroios", "38.71", "-9.14", "2026-06-23"]
        csv << ["Lisboa", "1", "Belm", "38.71", "-9.14", "2026-06-23"]
        %w[2 3 4 5].each { |number| csv << ["Lisboa", number, "missing", "38.71", "-9.14", "2026-06-23"] }
        csv << ["Lisboa", " ", "Arroios", "38.71", "-9.14", "2026-06-23"]
        csv << ["Lisboa", "406/UT/2017", "Arroios", "38.71", "-9.14", "2026-06-23"]
      end
      yield dir, airbnb, official
    end
  end

  def test_retains_all_entries_and_derives_an_independent_classification_view
    with_sources do |_dir, airbnb, official|
      sources = AlojamentoLocal::Analysis::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      retained = sources.official.entries.map { |entry| entry.raw.dup }
      listings, lookup = AlojamentoLocal::Analysis.classify(sources)
      metrics = AlojamentoLocal::Analysis::RegistrationMetrics.calculate(listings, sources.official)
      assert_equal CSV.read(official, headers: true).map(&:to_h), retained
      assert_equal retained, sources.official.entries.map(&:raw)
      assert_equal "First", lookup.fetch("1")["Denominacao"]
      assert_equal "Lisboa", lookup.fetch("1")["Concelho"]
      %w[2 3 4].each do |number|
        assert_nil lookup.fetch(number)["Concelho"]
        assert_nil lookup.fetch(number)["LatLong"]
        assert_equal "geografia oficial não identificada", listings.find { |row| row[:licensa] == number }[:license_group_assessment]
      end
      assert_nil sources.official.entries.first.raw["normalized_number"]
      assert_equal " Lisboa ", sources.official.entries.first.raw["Concelho"]
      assert_equal 10, metrics[:diagnostics][:national_entries]
      assert_equal 4, metrics[:diagnostics][:duplicate_number_extra_entries]
      assert_equal 1, metrics[:diagnostics][:unparseable_official_numbers]
      assert_equal [8, 4], metrics[:rows].first.values_at(:official_entries, :rnal)
      assert_equal [4, 4, 0], metrics[:rows].last.values_at(:airbnb, :airbnb_only, :intersection)
      assert_equal AlojamentoLocal::Analysis::RegistrationMetrics.calculate(listings, official), metrics
      assert_equal AlojamentoLocal::Analysis.analyse(airbnb, official), [listings, lookup]
    end
  end

  def test_normalized_municipality_filter_keeps_reuse_and_classification_in_sync
    with_sources do |_dir, airbnb, official|
      sources = AlojamentoLocal::Analysis::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      listings, = AlojamentoLocal::Analysis.classify(sources)
      assert_equal 10, listings.size
      assert_equal 4, sources.airbnb.licence_counts["1"]
      assert_equal sources.airbnb.entries.group_by(&:number).transform_values(&:size), sources.airbnb.licence_counts
      assert_equal ["Lisboa"], sources.airbnb.entries.map(&:municipality).uniq
      assert_equal ["Lisboa", " Lisboa ", "lisboa", "Lisboa"], sources.airbnb.entries.select { |entry| entry.number == "1" }.map { |entry| entry.raw["neighbourhood_group_cleansed"] }
      assert_equal ["licença reutilizada 4"], listings.select { |row| row[:licensa] == "1" }.map { |row| row[:license_status] }.uniq
      assert_equal ["Arroios", "Arroios", "Arroios", "Belém"], listings.select { |row| row[:licensa] == "1" }.map { |row| row[:bairro] }
      assert_equal ["001/AL", "1", "1", "1"], listings.select { |row| row[:licensa] == "1" }.map { |row| row[:licensa_raw] }
    end
  end

  def test_municipality_variants_contribute_to_spatial_rules_and_announcement_metrics
    with_sources do |_dir, airbnb, official|
      CSV.open(airbnb, "w", write_headers: true, headers: %w[neighbourhood_group_cleansed license neighbourhood_cleansed latitude longitude]) do |csv|
        ["Lisboa", " Lisboa ", "lisboa", "LISBOA", "Lísboa"].each_with_index do |municipality, index|
          csv << [municipality, "001/AL", "Arroios", index == 4 ? "38.80" : "38.71", "-9.14"]
        end
        csv << [" lisboa ", "2", "Arroios", "38.71", "-9.14"]
        csv << ["LISBOA", nil, "Arroios", "38.71", "-9.14"]
        csv << [" Lisboa ", "406/UT/2017", "Arroios", "38.71", "-9.14"]
        ["Porto", "Lisboa Oriente", "", nil, "unknown"].each do |municipality|
          csv << [municipality, "1", "Arroios", "38.71", "-9.14"]
        end
      end
      sources = AlojamentoLocal::Analysis::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      listings, = AlojamentoLocal::Analysis.classify(sources)
      assert_equal 8, listings.size
      assert_equal({"1" => 5, "2" => 1, nil => 2}, sources.airbnb.licence_counts)
      repeated = listings.select { |row| row[:licensa] == "1" }
      assert_equal [2], repeated.map { |row| row[:spatial_cluster_count] }.uniq
      assert_equal ["licença repetida em várias localizações"], repeated.map { |row| row[:license_group_assessment] }.uniq
      assert repeated.all? { |row| row[:license_status].include?("licença reutilizada 5") }
      assert_equal 8, AlojamentoLocal.establishment_estimate(listings)
      city = AlojamentoLocal::Analysis::RegistrationMetrics.calculate(listings, sources.official)[:rows].first
      assert_equal [8, 1, 1, 6, 6, 2], city.values_at(:announcements, :empty_licence, :unrecognised_licence, :identifiable_number, :confirmed_rnal_match, :airbnb)
    end
  end

  def test_full_run_parses_and_normalizes_each_source_once
    with_sources do |dir, airbnb, official|
      reads = Hash.new(0)
      parsed = []
      foreach = CSV.method(:foreach)
      parser = AlojamentoLocal.method(:parse_al_license)
      read = lambda do |path, *args, **options, &block|
        options = args.pop.merge(options) if args.last.is_a?(Hash)
        reads[path] += 1 if block
        foreach.call(path, *args, **options, &block)
      end
      parse = ->(value) { parsed << value; parser.call(value) }
      with_method(CSV, :foreach, read) do
        with_method(AlojamentoLocal, :parse_al_license, parse) do
          result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public",
            output_root: File.join(dir, "snapshots"), history_path: File.join(dir, "history", "summary.csv"))
          assert_equal 8, result[:summary][:official_registers_lisbon]
          assert_equal 10, result[:summary][:listings]
        end
      end
      assert_equal 1, reads[airbnb]
      assert_equal 1, reads[official]
      assert_equal 20, parsed.size # 10 official entries and 10 normalized-Lisbon rows
    end
  end

  def test_preparation_is_fresh_when_bytes_change_at_the_same_path
    with_sources do |_dir, airbnb, official|
      first = AlojamentoLocal::Analysis::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      File.write(official, "NrRNAL,Concelho,Freguesia\n99,Lisboa,Arroios\n")
      File.write(airbnb, "neighbourhood_group_cleansed,license,neighbourhood_cleansed\nLisboa,99,Arroios\n")
      second = AlojamentoLocal::Analysis::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      assert_equal 10, first.official.entries.size
      assert_equal ["99"], second.official.by_number.keys
      assert_equal ["99"], second.airbnb.entries.map(&:number)
    end
  end

  def test_site_loads_selected_json_once_and_keeps_measured_inputs_unmodified
    with_sources do |dir, airbnb, official|
      result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public",
        output_root: File.join(dir, "snapshots"), history_path: File.join(dir, "history", "summary.csv"))
      reads = Hash.new(0)
      original = File.method(:read)
      read = ->(path, *args, **options) { reads[path] += 1; original.call(path, *args, **options) }
      builder = AlojamentoLocal::SiteData.new(snapshots: File.join(dir, "snapshots"),
        distance_history: File.join(dir, "history", "distance_ranges.csv"),
        outside_region_history: File.join(dir, "history", "outside_regions.csv"))
      with_method(File, :read, read) do
        runs = builder.public_runs
        assert_equal result[:path], builder.measured_run(runs)
        data = builder.site_data(runs)
        assert_equal 24, data["districts"].size
        assert_equal 10, data["metrics"]["announcements"]
        assert_equal 8, data["official_count"]
        assert_equal "belm", data["districts"].find { |row| row["name"] == "Belém" }["slug"]
        assert_equal 1, reads[File.join(result[:path], "snapshot.json")]
        %w[metadata.json summary.json registration_metrics.json].each do |file|
          assert_equal 0, reads[File.join(result[:path], file)]
        end
        metrics = builder.load_json(File.join(result[:path], "snapshot.json")).fetch("registration_metrics")
        refute metrics.fetch("rows").first.key?("geometry")
        AlojamentoLocal::Analysis::RegistrationMetrics.validate!(JSON.parse(JSON.generate(metrics), symbolize_names: true))
      end
      # Existing published 2.0.0 snapshots remain readable with metric schema 1.0.0.
      snapshot = AlojamentoLocal::PublicSnapshot::Loader.new.load(result[:path])
      LegacySnapshot.write(result[:path], snapshot, methodology_version: "2.0.0")
      FileUtils.rm(File.join(result[:path], "snapshot.json"))
      legacy = AlojamentoLocal::SiteData.new(snapshots: File.join(dir, "snapshots"),
        distance_history: File.join(dir, "history", "distance_ranges.csv"),
        outside_region_history: File.join(dir, "history", "outside_regions.csv"))
      assert_equal result[:path], legacy.measured_run(legacy.public_runs)
      assert_equal 10, legacy.site_data(legacy.public_runs)["metrics"]["announcements"]
    end
  end

  def test_site_aliases_keep_display_names_and_existing_routes
    AlojamentoLocal::Geography::ALIASES.each do |source, canonical|
      assert_equal canonical, AlojamentoLocal::Geography.display_name(source)
      assert_equal canonical, AlojamentoLocal::Geography.parish(source)
      assert_equal source, AlojamentoLocal::Geography.route_name(canonical)
    end
    assert_equal "Arroios", AlojamentoLocal::Geography.route_name("Arroios")
    assert_equal "unknown", AlojamentoLocal::Geography.display_name("unknown")
  end
end
