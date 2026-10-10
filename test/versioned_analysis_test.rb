require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../lib/al_ilegal"

class VersionedAnalysisTest < Minitest::Test
  HEADERS = %w[neighbourhood_group_cleansed license listing_url neighbourhood_cleansed name latitude longitude room_type property_type bedrooms host_id last_scraped]

  def test_publication_audit_scans_binary_assets_without_encoding_errors
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "NOTICE"), "Attribution")
      image = File.join(dir, "favicon.png")
      File.binwrite(image, "\x89PNG\r\n\x1A\n\xFF".b)
      command = [RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", dir]

      output, status = Open3.capture2e(*command)
      assert status.success?, output

      File.binwrite(image, File.binread(image) + "https://example.com/rooms/123")
      output, status = Open3.capture2e(*command)
      refute status.success?
      assert_includes output, "URL de anúncio em favicon.png"
    end
  end

  def test_existing_public_run_is_detected_without_mutating_it
    Dir.mktmpdir do |dir|
      airbnb = File.join(dir, "listings-2026-06-23.csv")
      official = File.join(dir, "official-2026-09-19.csv")
      output_root = File.join(dir, "snapshots")
      File.write(airbnb, "fixture")
      File.write(official, "fixture")
      run_id = AlIlegal::Analysis.run_id_for(airbnb_path: airbnb, official_path: official)
      path = File.join(output_root, run_id)
      FileUtils.mkdir_p(path)
      meta = {methodology_version: AlIlegal::METHODOLOGY_VERSION, analysis_version: AlIlegal::ANALYSIS_VERSION,
              output_schema_version: AlIlegal::OUTPUT_SCHEMA_VERSION,
              mode: "public", source_files: {airbnb: {sha256: Digest::SHA256.file(airbnb).hexdigest}, official: {sha256: Digest::SHA256.file(official).hexdigest}}}
      File.write(File.join(path, "metadata.json"), JSON.generate(meta))
      (AlIlegal::PUBLIC_CSV_SCHEMAS.keys + %w[summary.json report.html registration_metrics.json]).each { |file| File.write(File.join(path, file), "fixture") }
      before = File.binread(File.join(path, "metadata.json"))
      existing = AlIlegal::Analysis.existing_public_run(airbnb_path: airbnb, official_path: official, output_root: output_root)
      assert_equal run_id, existing[:run_id]
      assert_equal before, File.binread(File.join(path, "metadata.json"))
      File.write(official, "changed bytes")
      assert_raises(RuntimeError) { AlIlegal::Analysis.existing_public_run(airbnb_path: airbnb, official_path: official, output_root: output_root) }
      assert_equal "2026-06-23__2026-09-19", run_id
      File.write(official, "fixture")
      meta[:methodology_version] = "1.1.0"
      File.write(File.join(path, "metadata.json"), JSON.generate(meta))
      assert_nil AlIlegal::Analysis.existing_public_run(airbnb_path: airbnb, official_path: official, output_root: output_root)
    end
  end

  def test_public_runs_replace_the_date_pair_outputs_and_history
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
      assert_equal %w[metadata.json report.html summary.json listings.csv licence_groups.csv freguesias.csv registration_metrics.json].sort, Dir.children(run_dir).sort
      public_listings = CSV.read(File.join(run_dir, "listings.csv"), headers: true)
      assert_equal 3, public_listings.length
      assert_equal 1, public_listings.find { |row| row["classification"] == "sem licença" }["listings"].to_i
      assert_equal 1, public_listings.find { |row| row["classification"] == "sem licença identificável" }["listings"].to_i
      summary = JSON.parse(File.read(File.join(run_dir, "summary.json")))
      assert_equal 1, summary.fetch("official_registers_lisbon")
      assert_equal "2.0.0", summary.fetch("methodology_version")
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
      assert_raises(RuntimeError) { AlIlegal::Analysis.append_history(File.join(dir, "history", "summary.csv"), result[:summary]) }
      assert_equal "4.0.0", JSON.parse(File.read(File.join(run_dir, "metadata.json"))) ["output_schema_version"]
      report = File.read(File.join(run_dir, "report.html"))
      assert_operator report.length, :>, 1_000
      assert_includes report, "Exemplos ilustrativos"
      assert_includes report, "Não correspondem a anúncios"
      assert_includes report, "Licença repetida em várias localizações"
      refute report.match?(%r{https?://[^<]+/rooms/|host[_ ]?id|Rua [A-Z]|\b\d{4,}/AL\b}i)
      File.write(File.join(run_dir, "obsolete.pdf"), "obsolete")
      repeated = AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: File.join(dir, "history", "summary.csv"))
      assert_equal result[:path], repeated[:path]
      assert_equal [result[:run_id]], Dir.children(File.join(dir, "snapshots"))
      assert_equal 1, CSV.read(File.join(dir, "history", "summary.csv"), headers: true).length
      assert_equal 4, CSV.read(File.join(dir, "history", "distance_ranges.csv"), headers: true).length
      assert_empty repeated[:summary][:historical_comparisons]
      refute File.exist?(File.join(run_dir, "obsolete.pdf"))
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
      assert_equal %w[freguesias_summary.csv licence_groups_detailed.csv listings_detailed.csv metadata_local.json report_local.html summary_local.json registration_metrics.json].sort, Dir.children(run_dir).sort
      detailed = CSV.read(File.join(run_dir, "listings_detailed.csv"), headers: true)
      assert_includes detailed.headers, "host_id"
      assert_includes detailed.headers, "licensa_raw"
      assert_equal "00123/AL", detailed.first["licensa_raw"]
      assert_equal "local", JSON.parse(File.read(File.join(run_dir, "metadata_local.json"))) ["mode"]
      refute Dir.exist?(File.join(dir, "snapshots"))
    end
  end

  def test_public_run_appends_distance_ranges_without_changing_snapshot_schema
    Dir.mktmpdir do |dir|
      airbnb = File.join(dir, "listings-2026-06-23.csv")
      official = File.join(dir, "official-2026-09-17.csv")
      history = File.join(dir, "history", "summary.csv")
      CSV.open(airbnb, "w", write_headers: true, headers: HEADERS) do |csv|
        csv << ["Lisboa", "123/AL", "https://example/1", "Alfama", "Apartment A", "38.71", "-9.14", "Entire home/apt", "Apartment", "1", "1", "2026-06-23"]
        csv << ["Lisboa", "123/AL", "https://example/2", "Alfama", "Apartment B", "38.73", "-9.14", "Entire home/apt", "Apartment", "1", "2", "2026-06-23"]
      end
      CSV.open(official, "w", write_headers: true, headers: %w[NrRNAL LatLong DataRegisto Denominacao Endereco Concelho Modalidade NrUtentes]) do |csv|
        csv << ["123", "38.71;-9.14", "2020-01-01", "Casa", "Rua", "Lisboa", "Apartamento", "2"]
      end

      result = AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: history)
      rows = CSV.read(File.join(dir, "history", "distance_ranges.csv"), headers: true)

      assert_equal 4, rows.size
      assert_equal 1, rows.sum { |row| row["licence_groups"].to_i }
      assert_equal "1", rows.find { |row| row["range"] == "2_5_km" }["licence_groups"]
      assert_equal 2, CSV.read(File.join(result[:path], "listings.csv"), headers: true).sum { |row| row["listings"].to_i }
      assert_equal %w[metadata.json report.html summary.json listings.csv licence_groups.csv freguesias.csv registration_metrics.json].sort, Dir.children(result[:path]).sort
      assert_raises(RuntimeError) { AlIlegal::Analysis.append_distance_history(File.join(dir, "history", "distance_ranges.csv"), result[:run_id], []) }
    end
  end

  def test_public_run_counts_outside_regions_per_announcement_and_separates_unknown
    Dir.mktmpdir do |dir|
      airbnb = File.join(dir, "listings-2026-06-23.csv")
      official = File.join(dir, "official-outside-regions-2026-09-17.csv")
      history = File.join(dir, "history", "summary.csv")
      CSV.open(airbnb, "w", write_headers: true, headers: HEADERS) do |csv|
        2.times { |index| csv << ["Lisboa", "123/AL", "https://example/#{index}", "Alfama", "Apartment", "38.71", "-9.14", "Entire home/apt", "Apartment", "1", "1", "2026-06-23"] }
        csv << ["Lisboa", "456/AL", "https://example/3", "Alfama", "Apartment", "38.71", "-9.14", "Entire home/apt", "Apartment", "1", "2", "2026-06-23"]
        csv << ["Lisboa", "789/AL", "https://example/4", "Alfama", "Apartment", "38.71", "-9.14", "Entire home/apt", "Apartment", "1", "3", "2026-06-23"]
      end
      CSV.open(official, "w", write_headers: true, headers: %w[NrRNAL LatLong DataRegisto Denominacao Endereco Concelho NUTSII Modalidade NrUtentes]) do |csv|
        csv << ["123", "38.71;-9.14", "2020-01-01", "Casa", "Rua", "Porto", "Norte", "Apartamento", "2"]
        csv << ["456", "38.71;-9.14", "2020-01-01", "Casa", "Rua", nil, "Norte", "Apartamento", "2"]
        csv << ["789", "38.71;-9.14", "2020-01-01", "Casa", "Rua", "Lisboa", "Grande Lisboa", "Apartamento", "2"]
      end

      result = AlIlegal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: history)
      rows = CSV.read(File.join(dir, "history", "outside_regions.csv"), headers: true)
      counts = rows.to_h { |row| [[row["resolution"], row["official_region"].to_s], row["listings"].to_i] }

      assert_equal({["resolved", "Norte"] => 2}, counts)
      assert_equal 2, counts.values.sum
      assert rows.all? { |row| row["region_method"] == "official_register_nutsii_v1" }
      assert_equal 2, CSV.read(File.join(result[:path], "listings.csv"), headers: true).select { |row| row["classification"] == "licença oficial fora de Lisboa" }.sum { |row| row["listings"].to_i }
      assert_raises(RuntimeError) { AlIlegal::Analysis.append_outside_region_history(File.join(dir, "history", "outside_regions.csv"), result[:run_id], []) }
    end
  end

  def test_discovers_latest_lisbon_snapshot_from_inside_airbnb_page
    page = <<~HTML
      <h3>Lisbon, Lisbon, Portugal</h3>
      <h4>23 June, 2026 (<a href="https://insideairbnb.com/explore">Explore</a>)</h4>
      <a href="https://data.insideairbnb.com/portugal/lisbon/lisbon/2026-06-23/data/listings.csv.gz">listings.csv.gz</a>
    HTML

    assert_equal ["2026-06-23", "https://data.insideairbnb.com/portugal/lisbon/lisbon/2026-06-23/data/listings.csv.gz"], AlIlegal::Data.latest_airbnb_snapshot(page)
    older = '<a href="https://data.insideairbnb.com/portugal/lisbon/lisbon/2025-09-21/data/listings.csv.gz">older</a>'
    unordered = page.sub('<h4>', older + '<h4>')
    assert_equal "2026-06-23", AlIlegal::Data.latest_airbnb_snapshot(unordered).first
    assert_raises(RuntimeError) { AlIlegal::Data.latest_airbnb_snapshot('<h3>Lisbon</h3>changed page') }
  end
  def test_replacement_updates_only_its_own_history_rows_and_preserves_other_dates
    Dir.mktmpdir do |dir|
      path = File.join(dir, "summary.csv")
      first = {run_id: "2026-06-23__2026-09-26", source_dates: {airbnb_snapshot_date: "2026-06-23", official_register_download_date: "2026-09-26"}, methodology_version: "1.1.0", listings: 10, licence_groups: 5, establishment_estimate: 8, generated_at: "before"}
      october = first.merge(run_id: "2026-06-23__2026-10-01", generated_at: "october")
      AlIlegal::Analysis.append_history(path, first)
      AlIlegal::Analysis.append_history(path, october)
      original_october = File.readlines(path).find { |line| line.start_with?(october[:run_id] + ",") }
      latest = first.merge(methodology_version: "2.0.0", establishment_estimate: 9, generated_at: "after")
      AlIlegal::Analysis.append_history(path, latest, replace: true)
      assert_equal original_october, File.readlines(path).find { |line| line.start_with?(october[:run_id] + ",") }
      rows = CSV.read(path, headers: true)
      assert_equal 2, rows.size
      assert_equal "2.0.0", rows.find { |row| row["run_id"] == first[:run_id] }["methodology_version"]
      comparisons = AlIlegal::Analysis.historical_comparisons(path, latest)
      assert_equal [october[:run_id]], comparisons.map { |row| row[:run_id] }
      assert_match(/incompatível/, comparisons.first[:status])
      regions = File.join(dir, "outside_regions.csv")
      AlIlegal::Analysis.append_outside_region_history(regions, first[:run_id], [{license_group_assessment: "licença oficial fora de Lisboa", official_concelho: "Porto", official_region: "Norte"}])
      AlIlegal::Analysis.append_outside_region_history(regions, first[:run_id], [], replace: true)
      assert_empty CSV.read(regions, headers: true)
    end
  end

  def test_failed_public_install_restores_previous_snapshot_and_history
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "staging")
      candidate = File.join(staging, "snapshot")
      destination = File.join(dir, "snapshot")
      history = File.join(dir, "history.csv")
      FileUtils.mkdir_p(candidate)
      FileUtils.mkdir_p(destination)
      File.write(File.join(candidate, "sentinel"), "new")
      File.write(File.join(destination, "sentinel"), "old")
      File.write(history, "old history")
      assert_raises(Errno::ENOENT) do
        AlIlegal::Analysis.publish_public_run!(candidate, destination, {File.join(staging, "missing.csv") => history}, staging)
      end
      assert_equal "old", File.read(File.join(destination, "sentinel"))
      assert_equal "old history", File.read(history)
    end
  end

end

require_relative "registration_metrics_test"

class VersionedAnalysisTest
  def test_report_category_bars_use_number_groups_as_denominator
    summary = {run_id: "test", mode: "public", generated_at: "test", listings: 100,
               licence_groups: 100, establishment_estimate: 100,
               classifications: {"licença única em Lisboa" => 75, "licença oficial fora de Lisboa" => 25}}
    metadata = {source_urls: {airbnb: "https://example.com", official: "https://example.org"}, methodology_version: "2.0.0", analysis_version: "3.0.1"}
    groups = [{classification: "licença única em Lisboa", licence_groups: 75, listings: 75, spatial_locations: 75},
              {classification: "licença oficial fora de Lisboa", licence_groups: 25, listings: 25, spatial_locations: 25}]
    html = AlIlegal::Report.html(metadata, summary, groups, [])
    assert_includes html, "width:75%"
    assert_includes html, "width:25%"
  end
end
