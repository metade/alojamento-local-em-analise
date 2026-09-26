require "minitest/autorun"
require "tmpdir"
require_relative "../lib/al_ilegal"

class VersionedAnalysisTest < Minitest::Test
  HEADERS = %w[neighbourhood_group_cleansed license listing_url neighbourhood_cleansed name latitude longitude room_type property_type bedrooms host_id last_scraped]

  def test_existing_public_run_is_detected_without_mutating_it
    Dir.mktmpdir do |dir|
      airbnb = File.join(dir, "listings-2026-06-23.csv")
      official = File.join(dir, "official-2026-09-19.csv")
      output_root = File.join(dir, "snapshots")
      FileUtils.mkdir_p(File.join(output_root, "2026-06-23__2026-09-19"))

      existing = AlIlegal::Analysis.existing_public_run(airbnb_path: airbnb, official_path: official, output_root: output_root)

      assert_equal "2026-06-23__2026-09-19", existing[:run_id]
      assert_equal File.join(output_root, existing[:run_id]), existing[:path]
    end
  end

  def test_creates_immutable_versioned_outputs_and_history
    Dir.mktmpdir do |dir|
      airbnb = File.join(dir, "listings.csv")
      official = File.join(dir, "official-2026-09-17.csv")
      CSV.open(airbnb, "w", write_headers: true, headers: HEADERS) do |csv|
        csv << ["Lisboa", "00123/AL", "https://example/1", "Alfama", "Apartment", "38.71", "-9.14", "Entire home/apt", "Apartment", "1", "1", "2026-06-23"]
        csv << ["Lisboa", nil, "https://example/2", "Alfama", "No licence", "38.72", "-9.14", "Entire home/apt", "Apartment", "1", "2", "2026-06-23"]
        csv << ["Lisboa", "406/UT/2017", "https://example/3", "Alfama", "Other scheme", "38.73", "-9.14", "Entire home/apt", "Apartment", "1", "3", "2026-06-23"]
      end
      CSV.open(official, "w", write_headers: true, headers: %w[NrRNAL LatLong DataRegisto Denominacao Endereco Concelho Modalidade NrUtentes]) do |csv|
        csv << ["123", "38.71;-9.14", "2020-01-01", "Casa", "Rua", "Lisboa", "Apartamento", "2"]
      end

      result = AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: File.join(dir, "history", "summary.csv"))
      run_dir = result[:path]
      assert_equal "2026-06-23__2026-09-17", result[:run_id]
      assert_equal %w[metadata.json report.html summary.json listings.csv licence_groups.csv freguesias.csv].sort, Dir.children(run_dir).sort
      public_listings = CSV.read(File.join(run_dir, "listings.csv"), headers: true)
      assert_equal 3, public_listings.length
      assert_equal 1, public_listings.find { |row| row["classification"] == "sem licença" }["listings"].to_i
      assert_equal 1, public_listings.find { |row| row["classification"] == "sem licença identificável" }["listings"].to_i
      summary = JSON.parse(File.read(File.join(run_dir, "summary.json")))
      assert_equal 1, summary.fetch("official_registers_lisbon")
      assert_equal "1.1.0", summary.fetch("methodology_version")
      assert_equal AlIlegal::PUBLIC_CSV_SCHEMAS["listings.csv"], public_listings.headers
      refute_includes public_listings.headers, "host_id"
      refute public_listings.to_csv.match?(%r{https?://|/rooms/})
      AlIlegal::PUBLIC_CSV_SCHEMAS.each do |filename, headers|
        public_csv = CSV.read(File.join(run_dir, filename), headers: true)
        assert_equal headers, public_csv.headers
        refute public_csv.to_csv.match?(%r{https?://|/rooms/})
      end
      metadata = JSON.parse(File.read(File.join(run_dir, "metadata.json")))
      refute metadata.to_s.match?(/host_id|listing_url|licensa_raw|latitude|longitude|official_address/i)
      refute metadata.to_s.include?("path")
      assert_equal "3.1.0", JSON.parse(File.read(File.join(run_dir, "metadata.json"))) ["output_schema_version"]
      report = File.read(File.join(run_dir, "report.html"))
      assert_operator report.length, :>, 1_000
      assert_includes report, "Exemplos ilustrativos"
      assert_includes report, "Não correspondem a anúncios"
      assert_includes report, "Licença repetida em várias localizações"
      refute report.match?(%r{https?://[^<]+/rooms/|host[_ ]?id|Rua [A-Z]|\b\d{4,}/AL\b}i)
      assert_raises(RuntimeError) { AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: File.join(dir, "history", "summary.csv")) }
    end
  end

  def test_force_creates_a_preserved_local_rerun
    Dir.mktmpdir do |dir|
      airbnb = File.join(dir, "listings-2026-06-23.csv")
      official = File.join(dir, "official-2026-09-17.csv")
      CSV.open(airbnb, "w", write_headers: true, headers: HEADERS) do |csv|
        csv << ["Lisboa", "00123/AL", "https://example/1", "Alfama", "Apartment", "38.71", "-9.14", "Entire home/apt", "Apartment", "1", "host-1", "2026-06-23"]
      end
      CSV.open(official, "w", write_headers: true, headers: %w[NrRNAL LatLong DataRegisto Denominacao Endereco Concelho Modalidade NrUtentes]) do |csv|
        csv << ["123", "38.71;-9.14", "2020-01-01", "Casa", "Rua", "Lisboa", "Apartamento", "2"]
      end

      root = File.join(dir, "private")
      history = File.join(dir, "private", "history", "summary.csv")
      first = AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "local", output_root: root, history_path: history)
      rerun = AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "local", output_root: root, history_path: history, force: true)

      assert_equal "2026-06-23__2026-09-17", first[:run_id]
      assert_match(/\A2026-06-23__2026-09-17__rerun-\d{8}T\d{12}\z/, rerun[:run_id])
      assert Dir.exist?(first[:path])
      assert Dir.exist?(rerun[:path])
      assert_equal 2, CSV.read(history, headers: true).length
    end
  end

  def test_local_mode_writes_diagnostics_to_distinct_local_outputs
    Dir.mktmpdir do |dir|
      airbnb = File.join(dir, "listings-2026-06-23.csv")
      official = File.join(dir, "official-2026-09-17.csv")
      CSV.open(airbnb, "w", write_headers: true, headers: HEADERS) do |csv|
        csv << ["Lisboa", "00123/AL", "https://example/1", "Alfama", "Apartment", "38.71", "-9.14", "Entire home/apt", "Apartment", "1", "host-1", "2026-06-23"]
      end
      CSV.open(official, "w", write_headers: true, headers: %w[NrRNAL LatLong DataRegisto Denominacao Endereco Concelho Modalidade NrUtentes]) do |csv|
        csv << ["123", "38.71;-9.14", "2020-01-01", "Casa", "Rua", "Lisboa", "Apartamento", "2"]
      end

      result = AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "local", output_root: File.join(dir, "private"), history_path: File.join(dir, "private", "history", "summary.csv"))
      run_dir = result[:path]
      assert_equal %w[freguesias_summary.csv licence_groups_detailed.csv listings_detailed.csv metadata_local.json report_local.html summary_local.json].sort, Dir.children(run_dir).sort
      detailed = CSV.read(File.join(run_dir, "listings_detailed.csv"), headers: true)
      assert_includes detailed.headers, "host_id"
      assert_includes detailed.headers, "licensa_raw"
      assert_equal "local", JSON.parse(File.read(File.join(run_dir, "metadata_local.json"))) ["mode"]
      refute Dir.exist?(File.join(dir, "snapshots"))
    end
  end

  def test_discovers_latest_lisbon_snapshot_from_inside_airbnb_page
    page = <<~HTML
      <h3>Lisbon, Lisbon, Portugal</h3>
      <h4>23 June, 2026 (<a href="https://insideairbnb.com/explore">Explore</a>)</h4>
      <a href="https://data.insideairbnb.com/portugal/lisbon/lisbon/2026-06-23/data/listings.csv.gz">listings.csv.gz</a>
    HTML

    assert_equal ["2026-06-23", "https://data.insideairbnb.com/portugal/lisbon/lisbon/2026-06-23/data/listings.csv.gz"], AlIlegal::Data.latest_airbnb_snapshot(page)
  end
end
