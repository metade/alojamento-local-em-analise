require "minitest/autorun"
require "tmpdir"
require_relative "../lib/alojamento_local"
require_relative "../lib/alojamento_local/site_data"

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
      sources = AlojamentoLocal::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      retained = sources.official.entries.map { |entry| entry.raw.dup }
      listings, lookup = AlojamentoLocal::Analysis.classify(sources)
      metrics = AlojamentoLocal::RegistrationMetrics.calculate(listings, sources.official)
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
      assert_equal AlojamentoLocal::RegistrationMetrics.calculate(listings, official), metrics
      assert_equal AlojamentoLocal::Analysis.analyse(airbnb, official), [listings, lookup]
    end
  end

  def test_preserves_exact_municipality_filter_and_pre_filter_reuse_counts
    with_sources do |_dir, airbnb, official|
      sources = AlojamentoLocal::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      listings, = AlojamentoLocal::Analysis.classify(sources)
      assert_equal 8, listings.size
      assert_equal 4, sources.airbnb.licence_counts["1"]
      assert_equal ["licença reutilizada 4"], listings.select { |row| row[:licensa] == "1" }.map { |row| row[:license_status] }.uniq
      assert_equal ["Arroios", "Belém"], listings.select { |row| row[:licensa] == "1" }.map { |row| row[:bairro] }
      assert_equal ["001/AL", "1"], listings.select { |row| row[:licensa] == "1" }.map { |row| row[:licensa_raw] }
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
          assert_equal 8, result[:summary][:listings]
        end
      end
      assert_equal 1, reads[airbnb]
      assert_equal 1, reads[official]
      assert_equal 20, parsed.size # 10 official entries and 10 normalized-Lisbon rows
    end
  end

  def test_preparation_is_fresh_when_bytes_change_at_the_same_path
    with_sources do |_dir, airbnb, official|
      first = AlojamentoLocal::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      File.write(official, "NrRNAL,Concelho,Freguesia\n99,Lisboa,Arroios\n")
      File.write(airbnb, "neighbourhood_group_cleansed,license,neighbourhood_cleansed\nLisboa,99,Arroios\n")
      second = AlojamentoLocal::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
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
        assert_equal 8, data["metrics"]["announcements"]
        assert_equal 8, data["official_count"]
        assert_equal "belm", data["districts"].find { |row| row["name"] == "Belém" }["slug"]
        %w[metadata.json summary.json registration_metrics.json].each do |file|
          assert_equal 1, reads[File.join(result[:path], file)]
        end
        metrics = builder.load_json(File.join(result[:path], "registration_metrics.json"))
        refute metrics.fetch("rows").first.key?("geometry")
        AlojamentoLocal::RegistrationMetrics.validate!(JSON.parse(JSON.generate(metrics), symbolize_names: true))
      end
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
