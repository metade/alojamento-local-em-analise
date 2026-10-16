require "liquid"
require "minitest/autorun"
require "minitest/mock"
require "open3"
require "tmpdir"
require_relative "../lib/alojamento_local"

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

  def test_source_hash_guard_preserves_existing_snapshot
    Dir.mktmpdir do |dir|
      airbnb = File.expand_path("fixtures/pipeline/sources/listings-2024-06-01.csv", __dir__)
      official = File.join(dir, "official-2024-07-01.csv")
      FileUtils.cp(File.expand_path("fixtures/pipeline/sources/official-2024-07-01.csv", __dir__), official)
      output_root = File.join(dir, "snapshots")
      result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public",
        output_root: output_root, history_path: File.join(dir, "history", "summary.csv"))
      path = result.fetch(:path)
      before = File.binread(File.join(path, "snapshot.json"))
      hashes = [airbnb, official].map { |source| Digest::SHA256.file(source).hexdigest }
      AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, hashes)
      assert_equal before, File.binread(File.join(path, "snapshot.json"))
      File.write(official, "changed bytes")
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, [hashes.first, Digest::SHA256.file(official).hexdigest]) }
      FileUtils.cp(File.expand_path("fixtures/pipeline/sources/official-2024-07-01.csv", __dir__), official)
      data = JSON.parse(before)
      data["metadata"]["analysis_version"] = "3.2.0"
      File.write(File.join(path, "snapshot.json"), JSON.generate(data))
      AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, hashes)
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

      result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: File.join(dir, "history", "summary.csv"))
      run_dir = result[:path]
      assert_equal "2026-06-23__2026-09-17", result[:run_id]
      assert_equal %w[snapshot.json].sort, Dir.children(run_dir).sort
      snapshot = AlojamentoLocal::PublicSnapshot::Loader.new.load(run_dir)
      public_listings = snapshot.published_announcement_rows
      assert_equal 3, public_listings.length
      assert_equal 1, public_listings.find { |row| row["classification"] == "sem licença" }["listings"].to_i
      assert_equal 1, public_listings.find { |row| row["classification"] == "sem licença identificável" }["listings"].to_i
      assert_equal 1, snapshot.summary.fetch("official_registers_lisbon")
      assert_equal "2.1.0", snapshot.summary.fetch("methodology_version")
      assert_equal "6.0.0", snapshot.metadata.fetch("output_schema_version")
      refute JSON.generate(snapshot.to_h).match?(/host_id|listing_url|licensa_raw|latitude|longitude|official_address/i)
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::History.append_history(File.join(dir, "history", "summary.csv"), result[:summary]) }
      File.write(File.join(run_dir, "obsolete.pdf"), "obsolete")
      repeated = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: File.join(dir, "history", "summary.csv"))
      assert_equal result[:path], repeated[:path]
      assert_equal [result[:run_id]], Dir.children(File.join(dir, "snapshots"))
      assert_equal 1, CSV.read(File.join(dir, "history", "summary.csv"), headers: true).length
      assert_equal 4, CSV.read(File.join(dir, "history", "distance_ranges.csv"), headers: true).length
      assert_empty repeated[:summary][:historical_comparisons]
      refute File.exist?(File.join(run_dir, "obsolete.pdf"))
    end
  end

  def test_repeated_analysis_creates_a_preserved_local_rerun
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
      first = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "local", output_root: root, history_path: history)
      rerun = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "local", output_root: root, history_path: history)

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

      result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "local", output_root: File.join(dir, "private"), history_path: File.join(dir, "private", "history", "summary.csv"))
      run_dir = result[:path]
      assert_equal %w[licence_groups_detailed.csv listings_detailed.csv snapshot.json].sort, Dir.children(run_dir).sort
      detailed = CSV.read(File.join(run_dir, "listings_detailed.csv"), headers: true)
      assert_includes detailed.headers, "host_id"
      assert_includes detailed.headers, "licensa_raw"
      assert_equal "00123/AL", detailed.first["licensa_raw"]
      assert_equal "local", JSON.parse(File.read(File.join(run_dir, "snapshot.json"))).fetch("metadata").fetch("mode")
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

      result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: history)
      rows = CSV.read(File.join(dir, "history", "distance_ranges.csv"), headers: true)

      assert_equal 4, rows.size
      assert_equal 1, rows.sum { |row| row["licence_groups"].to_i }
      assert_equal "1", rows.find { |row| row["range"] == "2_5_km" }["licence_groups"]
      assert_equal 2, AlojamentoLocal::PublicSnapshot::Loader.new.load(result[:path]).published_announcement_rows.sum { |row| row["listings"].to_i }
      assert_equal %w[snapshot.json].sort, Dir.children(result[:path]).sort
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::History.append_distance_history(File.join(dir, "history", "distance_ranges.csv"), result[:run_id], []) }
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

      result = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public", output_root: File.join(dir, "snapshots"), history_path: history)
      rows = CSV.read(File.join(dir, "history", "outside_regions.csv"), headers: true)
      counts = rows.to_h { |row| [[row["resolution"], row["official_region"].to_s], row["listings"].to_i] }

      assert_equal({["resolved", "Norte"] => 2}, counts)
      assert_equal 2, counts.values.sum
      assert rows.all? { |row| row["region_method"] == "official_register_nutsii_v1" }
      assert_equal 2, AlojamentoLocal::PublicSnapshot::Loader.new.load(result[:path]).published_announcement_rows.select { |row| row["classification"] == "licença oficial fora de Lisboa" }.sum { |row| row["listings"].to_i }
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::History.append_outside_region_history(File.join(dir, "history", "outside_regions.csv"), result[:run_id], []) }
    end
  end

  def test_discovers_latest_lisbon_snapshot_from_inside_airbnb_page
    page = <<~HTML
      <h3>Lisbon, Lisbon, Portugal</h3>
      <h4>23 June, 2026 (<a href="https://insideairbnb.com/explore">Explore</a>)</h4>
      <a href="https://data.insideairbnb.com/portugal/lisbon/lisbon/2026-06-23/data/listings.csv.gz">listings.csv.gz</a>
    HTML

    assert_equal ["2026-06-23", "https://data.insideairbnb.com/portugal/lisbon/lisbon/2026-06-23/data/listings.csv.gz"], AlojamentoLocal::Analysis::Data.latest_airbnb_snapshot(page)
    older = '<a href="https://data.insideairbnb.com/portugal/lisbon/lisbon/2025-09-21/data/listings.csv.gz">older</a>'
    unordered = page.sub('<h4>', older + '<h4>')
    assert_equal "2026-06-23", AlojamentoLocal::Analysis::Data.latest_airbnb_snapshot(unordered).first
    assert_raises(RuntimeError) { AlojamentoLocal::Analysis::Data.latest_airbnb_snapshot('<h3>Lisbon</h3>changed page') }
  end
  def test_replacement_updates_only_its_own_history_rows_and_preserves_other_dates
    Dir.mktmpdir do |dir|
      path = File.join(dir, "summary.csv")
      first = {run_id: "2026-06-23__2026-09-26", source_dates: {airbnb_snapshot_date: "2026-06-23", official_register_download_date: "2026-09-26"}, methodology_version: "1.1.0", listings: 10, licence_groups: 5, establishment_estimate: 8, generated_at: "before"}
      october = first.merge(run_id: "2026-06-23__2026-10-01", generated_at: "october")
      AlojamentoLocal::Analysis::History.append_history(path, first)
      AlojamentoLocal::Analysis::History.append_history(path, october)
      original_october = File.readlines(path).find { |line| line.start_with?(october[:run_id] + ",") }
      latest = first.merge(methodology_version: "2.0.0", establishment_estimate: 9, generated_at: "after")
      AlojamentoLocal::Analysis::History.append_history(path, latest, replace: true)
      assert_equal original_october, File.readlines(path).find { |line| line.start_with?(october[:run_id] + ",") }
      rows = CSV.read(path, headers: true)
      assert_equal 2, rows.size
      assert_equal "2.0.0", rows.find { |row| row["run_id"] == first[:run_id] }["methodology_version"]
      comparisons = AlojamentoLocal::Analysis::History.historical_comparisons(path, latest)
      assert_equal [october[:run_id]], comparisons.map { |row| row[:run_id] }
      assert_match(/incompatível/, comparisons.first[:status])
      regions = File.join(dir, "outside_regions.csv")
      AlojamentoLocal::Analysis::History.append_outside_region_history(regions, first[:run_id], [{license_group_assessment: "licença oficial fora de Lisboa", official_concelho: "Porto", official_region: "Norte"}])
      AlojamentoLocal::Analysis::History.append_outside_region_history(regions, first[:run_id], [], replace: true)
      assert_empty CSV.read(regions, headers: true)
    end
  end

  def test_failed_public_install_restores_previous_snapshot_and_history
    Dir.mktmpdir do |dir|
      airbnb = File.expand_path("fixtures/pipeline/sources/listings-2024-06-01.csv", __dir__)
      official = File.expand_path("fixtures/pipeline/sources/official-2024-07-01.csv", __dir__)
      output_root = File.join(dir, "snapshots")
      history = File.join(dir, "history", "summary.csv")
      published = AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official, mode: "public",
        output_root: output_root, history_path: history)
      destination = published.fetch(:path)
      sources = AlojamentoLocal::Analysis::PreparedSources::Pair.new(airbnb_path: airbnb, official_path: official)
      listings, = AlojamentoLocal::Analysis::Classifier.new(sources).classify
      publisher = AlojamentoLocal::Analysis::PublicPublisher.new(destination: destination, history_path: history)
      read_files = -> do
        Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h do |path|
          [path, File.binread(path)]
        end
      end
      before = read_files.call
      move = FileUtils.method(:mv)
      distance_history = File.join(File.dirname(history), "distance_ranges.csv")

      [Errno::EIO, Interrupt].each do |failure_class|
        fail_install = ->(source, target, **options) do
          # Fail after the snapshot and summary are installed, and after the
          # existing distance history has been moved to its staging backup.
          raise failure_class, "Injected install failure" if File.basename(source) == "distance_ranges.csv" && target == distance_history

          move.call(source, target, **options)
        end
        FileUtils.stub(:mv, fail_install) do
          assert_raises(failure_class) do
            publisher.publish(summary: published.fetch(:summary).merge(generated_at: "replacement"), listings: listings) do |run_dir|
              FileUtils.cp_r(destination, run_dir)
              snapshot_file = File.join(run_dir, "snapshot.json")
              document = JSON.parse(File.read(snapshot_file))
              document["summary"]["generated_at"] = "replacement"
              File.write(snapshot_file, JSON.generate(document))
            end
          end
        end
        assert_equal before, read_files.call
        assert_empty Dir.glob(File.join(output_root, ".analysis-*"))
      end
    end
  end

end

require_relative "registration_metrics_test"

class VersionedAnalysisTest
  def test_report_category_bars_use_number_groups_as_denominator
    data = JSON.parse(File.read(File.expand_path("fixtures/pipeline/expected/public/snapshot.json", __dir__)))
    data["summary"]["licence_groups"] = 100
    data["summary"]["listings"] = 400
    data["summary"]["classifications"] = {"unique" => 75, "outside" => 25}
    source = File.read(File.expand_path("../site/report.html", __dir__)).sub(/\A---.*?---\n/m, "")
    template = Liquid::Template.parse(source)
    html = template.render!("page" => {"report" => data})
    assert_equal ["75", "25"], html.scan(/style="width:(\d+)%"/).flatten
    data["summary"]["licence_groups"] = 0
    html = template.render!("page" => {"report" => data})
    assert_equal ["0", "0"], html.scan(/style="width:(\d+)%"/).flatten

  end
end

require_relative "prepared_sources_test"
require_relative "pipeline_regression_test"
