require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "support/candidate_fixture"

class CandidateDatasetTest < Minitest::Test
  def with_data
    Dir.mktmpdir do |path|
      FileUtils.cp(Dir[File.join(CandidateFixture::PATH, "*.json")], path)
      yield path
    end
  end

  def change(path)
    filename = File.join(path, "snapshot.json")
    data = JSON.parse(File.read(filename))
    yield data
    File.write(filename, JSON.generate(data))
  end

  def test_hand_counted_fixture_and_many_to_many_accounting
    data = AlojamentoLocal::SiteData.new(dataset: CandidateFixture.dataset).site_data
    assert_equal 12, data.dig("summary", "candidate_count")
    assert_equal 13, data.dig("summary", "listing_count")
    assert_equal 7, data.dig("summary", "distinct_al_numbers")
    assert_equal 12, data.dig("metrics", "airbnb"), "Airbnb includes unnumbered candidates and repeated numbers"
    assert_equal 17, data.dig("summary", "official_numbers")
    assert_equal 12, data["districts"].sum { |d| d["candidate_count"] } + data.dig("unknown", "candidate_count")
    assert_equal 24, data["districts"].size
    arroios = data["districts"].find { |d| d["name"] == "Arroios" }
    assert_equal [5, 8, 4], arroios.values_at("candidate_count", "listing_count", "distinct_al_numbers")
    assert_equal 5, arroios.dig("metrics", "airbnb")
    assert_equal 2, data["candidates"].count { |c| c["listing_ids"].include?("demo-105") }
    assert_equal 3, data["candidates"][1]["listing_count"]
    assert_equal 2, data["candidates"].count { |c| c["al_number"] == "100005" }
    assert_equal 8, data.dig("metrics", "intersection"), "Counts every numbered candidate, including reuse and numbers not found locally"
    assert_equal 4, data.dig("metrics", "airbnb_only")
    assert_equal 9, data.dig("metrics", "rnal_only")
    assert data.dig("metrics", "geometry")
    assert_equal [4, 1], arroios.fetch("metrics").values_at("intersection", "airbnb_only")
    assert_equal 0, data["districts"].find { |d| d["name"] == "Ajuda" }["candidate_count"]
    assert_equal "belm", data["districts"].find { |d| d["name"] == "Belém" }["slug"]
  end

  def test_numbered_candidates_exceeding_rnal_keep_counts_without_invalid_geometry
    document = JSON.parse(JSON.generate(CandidateFixture.dataset.document))
    document["rnal"]["lisbon"]["count"] = 0
    document["rnal"]["parishes"].each { |row| row["count"] = 0 }
    dataset = AlojamentoLocal::CandidateDataset.new(document: document)
    metrics = AlojamentoLocal::SiteData.new(dataset: dataset).site_data.fetch("metrics")
    assert_equal [12, 8, 4], metrics.values_at("airbnb", "intersection", "airbnb_only")
    assert_nil metrics["geometry"]
  end

  def test_unidentified_licence_signal_counts_listings_and_excludes_exemptions
    signals = AlojamentoLocal::SiteData.new(dataset: CandidateFixture.dataset).site_data.fetch("signals")
    assert_equal [2, 1, 1], signals.values_at("unidentified_licence_listings", "empty_licence_listings", "unrecognised_licence_listings")
    with_data do |path|
      change(path) do |document|
        empty = document["candidates"].find { |candidate| candidate["id"] == "candidate-011" }
        document["candidates"] << empty.merge("id" => "another-reference-to-empty-listing")
        unrecognised = document["candidates"].find { |candidate| candidate["id"] == "candidate-010" }
        unrecognised["listing_ids"] << "demo-114"
        unrecognised["listing_count"] = 2
        document["listings"]["lisbon"]["count"] += 1
        document["listings"]["parishes"].find { |row| row["freguesia"] == "Belém" }["count"] += 1
      end
      signals = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data.fetch("signals")
      assert_equal [3, 1, 2], signals.values_at("unidentified_licence_listings", "empty_licence_listings", "unrecognised_licence_listings")
      change(path) { |document| document["candidates"] = [] }
      signals = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data.fetch("signals")
      assert_equal [0, 0, 0], signals.values_at("unidentified_licence_listings", "empty_licence_listings", "unrecognised_licence_listings")
    end
  end

  def test_outside_regions_count_distinct_listings_and_resolve_ambiguous_regions
    data = AlojamentoLocal::SiteData.new(dataset: CandidateFixture.dataset).site_data
    assert_equal 1, data.dig("signals", "outside_listings")
    assert_equal [{"name" => "Algarve", "count" => 1, "unresolved" => false, "width" => 100.0}], data.dig("outside_regions", "rows")
    with_data do |path|
      change(path) do |document|
        candidate = document["candidates"].last
        candidate["listing_ids"] << "demo-114"
        candidate["listing_count"] = 2
        document["listings"]["lisbon"]["count"] += 1
        document["listings"]["parishes"].find { |row| row["freguesia"] == "Arroios" }["count"] += 1
        other = JSON.parse(JSON.generate(candidate))
        other["id"] = "another-number-for-the-same-listings"
        other["al_number"] = "100008"
        document["candidates"] << other
      end
      data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
      assert_equal 2, data.dig("outside_regions", "rows", 0, "count")
      assert_equal 2, data.dig("signals", "outside_listings")
      [nil, "Centro"].each do |region|
        change(path) { |document| document["candidates"].last["official_match"]["district"] = region }
        data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
        assert_equal [{"name" => "Região por resolver", "count" => 2, "unresolved" => true, "width" => 100.0}], data.dig("outside_regions", "rows")
      end
      change(path) { |document| document["candidates"] = [] }
      data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
      assert_equal 0, data.dig("signals", "outside_listings")
      assert_empty data.dig("outside_regions", "rows")
    end
  end

  def test_reuse_distances_count_each_number_once_including_three_locations
    data = AlojamentoLocal::SiteData.new(dataset: CandidateFixture.dataset).site_data
    assert_equal 2, data.dig("signals", "repeated_listings")
    assert_equal 1, data["distance_total"]
    assert_equal [0, 0, 0, 0, 1], data["distance_ranges"].map { |row| row["count"] }
    assert_equal 100.0, data["distance_ranges"].last["width"]
    with_data do |path|
      change(path) do |document|
        candidate = document["candidates"][1]
        candidate["al_number"] = "100005"
        candidate["official_match"]["distance_km"] = 1.2
      end
      data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
      assert_equal 5, data.dig("signals", "repeated_listings"), "Includes all three listings in a grouped candidate"
      assert_equal 1, data["distance_total"], "Three candidates with one number still contribute once"
      assert_equal [0, 0, 0, 0, 1], data["distance_ranges"].map { |row| row["count"] }, "Uses the maximum of 6.2 km rather than an average"
      change(path) { |document| document["candidates"][1]["official_match"]["distance_km"] = nil }
      data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
      assert_equal({"label" => "Distância por resolver", "count" => 1, "unresolved" => true, "width" => 100.0}, data["distance_ranges"].last)
      assert_equal 1, data["distance_ranges"].sum { |row| row["count"] }
      change(path) { |document| document["candidates"] = [] }
      data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
      assert_equal 0, data["distance_total"]
      assert_equal 0, data.dig("signals", "repeated_listings")
      assert_empty data["distance_ranges"]
    end
  end

  def test_reuse_distance_interval_boundaries_preserve_zero
    document = JSON.parse(JSON.generate(CandidateFixture.dataset.document))
    [[0, 0], [0.5, 0], [0.5001, 1], [1, 1], [1.0001, 2], [2, 2], [2.0001, 3], [5, 3], [5.0001, 4]].each do |distance, expected|
      document["candidates"].select { |candidate| candidate["al_number"] == "100005" }.each { |candidate| candidate["official_match"]["distance_km"] = distance }
      dataset = AlojamentoLocal::CandidateDataset.new(document: document)
      rows = AlojamentoLocal::SiteData.new(dataset: dataset).site_data.fetch("distance_ranges")
      assert_equal 1, rows[expected]["count"], "Distance #{distance} km"
      assert_equal 1, rows.sum { |row| row["count"] }
    end
  end

  def test_official_match_is_one_nullable_record_with_its_distance
    candidates = CandidateFixture.dataset.candidates
    assert_equal 217.0, candidates.last.dig("official_match", "distance_km")
    assert_nil candidates.find { |candidate| candidate["registration_status"] == "not_found" }["official_match"]
    candidates.each do |candidate|
      assert_equal candidate["registration_status"] == "found", candidate["official_match"].is_a?(Hash)
      refute candidate.key?("official_matches")
      refute candidate.key?("distance_to_rnal_km")
      refute candidate.key?("reuse")
    end
    [
      ->(candidate) { candidate["official_match"] = [candidate["official_match"]] },
      ->(candidate) { candidate["official_match"] = nil },
      ->(candidate) { candidate["registration_status"] = "not_found" }
    ].each do |mutation|
      with_data do |path|
        change(path) { |document| mutation.call(document["candidates"].first) }
        assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.new(path) }
      end
    end
  end

  def test_snapshot_contract_has_no_fixture_metadata_or_mode
    dataset = CandidateFixture.dataset
    assert_equal %w[candidates listings rnal source_dates], dataset.document.keys.sort
    assert_equal %w[lisbon parishes], dataset.rnal.keys.sort
    assert_equal 13, dataset.listings.dig("lisbon", "count")
    dataset.candidates.each do |candidate|
      assert_equal %w[airbnb_freguesias coordinate_freguesia], candidate.fetch("geography").keys.sort
      %w[correspondence_assessment correspondence_reasons exemption].each do |field|
        refute candidate.key?(field)
      end
    end
    assert_equal 2, dataset.candidates.count { |candidate| candidate["registration_status"] == "exempt" }
    with_data do |path|
      change(path) { |d| d["synthetic"] = true }
      assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.new(path) }
    end
  end

  def test_source_dates_are_loaded_without_conflating_fetch_and_snapshot_dates
    data = AlojamentoLocal::SiteData.new(dataset: CandidateFixture.dataset).site_data
    assert_equal({"rnal_fetched_on" => "2024-07-01", "airbnb_fetched_on" => "2024-06-03", "airbnb_snapshot_date" => "2024-06-01"}, data.fetch("source_dates"))
    [nil, "2024-02-30", "01/07/2024"].each do |invalid|
      with_data do |path|
        change(path) { |d| d["source_dates"]["rnal_fetched_on"] = invalid }
        assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.new(path) }
      end
    end
  end

  def test_rnal_summary_has_one_count_and_uses_the_json_schema
    dataset = CandidateFixture.dataset
    assert_equal({"count" => 17}, dataset.rnal.fetch("lisbon"))
    assert dataset.rnal.fetch("parishes").all? { |row| row.keys.sort == %w[count freguesia] }
    assert AlojamentoLocal::CandidateDataset::SCHEMA.valid?(dataset.document)
    data = JSON.parse(JSON.generate(dataset.document))
    data["candidates"][0]["official_match"]["address"] = "private"
    refute AlojamentoLocal::CandidateDataset::SCHEMA.valid?(data)
    error = assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.validate!(data) }
    assert_includes error.message, "snapshot schema"
  end

  def test_rnal_distinct_counts_can_overlap_across_parishes
    data = JSON.parse(JSON.generate(CandidateFixture.dataset.document))
    data["rnal"]["lisbon"]["count"] = 1
    data["rnal"]["parishes"].each { |row| row["count"] = %w[Arroios Estrela].include?(row["freguesia"]) ? 1 : 0 }
    AlojamentoLocal::CandidateDataset.validate!(data)
  end

  def test_original_listing_geography_is_independent_of_candidate_assignment
    data = AlojamentoLocal::SiteData.new(dataset: CandidateFixture.dataset).site_data
    arroios = data["districts"].find { |d| d["name"] == "Arroios" }
    estrela = data["districts"].find { |d| d["name"] == "Estrela" }
    assert_equal [8, 5], arroios.values_at("listing_count", "candidate_count")
    assert_equal [0, 1], estrela.values_at("listing_count", "candidate_count")
    assert_equal 13, data["districts"].sum { |d| d["listing_count"] } + data.dig("unknown", "listing_count")
  end

  def test_rejects_invalid_original_listing_accounting
    [
      ->(d) { d["listings"]["lisbon"]["count"] += 1 },
      ->(d) { d["listings"]["parishes"][0]["count"] = -1 },
      ->(d) { d["listings"]["parishes"] << d["listings"]["parishes"][0] },
      ->(d) {
        d["listings"]["lisbon"]["count"] = 0
        d["listings"]["parishes"].each { |row| row["count"] = 0 }
      }
    ].each do |mutation|
      with_data do |path|
        change(path, &mutation)
        assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.new(path) }
      end
    end
  end

  def test_number_lookup_retains_official_geography
    candidate = CandidateFixture.dataset.candidates.last
    assert_equal "found", candidate["registration_status"]
    assert_equal "Arroios", candidate["freguesia"]
    assert_equal "Faro", candidate["official_match"]["municipality"]
  end

  def test_rejects_corruption_and_private_fields_at_every_depth
    mutations = [
      ->(d) { d["candidates"][0]["address"] = "private" },
      ->(d) { d["candidates"][0]["official_match"]["latitude"] = 38.7 },
      ->(d) { d["host_id"] = "private" },
      ->(d) { d["candidates"][0]["listing_count"] = 99 },
      ->(d) { d["candidates"][0]["listing_ids"] *= 2 },
      ->(d) { d["candidates"][0]["id"] = d["candidates"][1]["id"] },
      ->(d) { d["candidates"][0]["al_number"] = ["1", "2"] },
      ->(d) { d["candidates"][0]["registration_status"] = "verified" },
      ->(d) { d["candidates"][0]["registration_status"] = "not_found" },
      ->(d) { d["candidates"][0]["al_number"] = nil },
      ->(d) { d["candidates"][0]["freguesia"] = "Faro" },
      ->(d) { d["candidates"][0]["official_match"]["distance_km"] = -1 },
      ->(d) { d["candidates"][0]["reuse"] = {"candidate_count" => 1} },
      ->(d) { d["candidates"][0]["listing_ids"] = ["https://www.airbnb.com/rooms/123"] }
    ]
    mutations.each do |mutation|
      with_data do |path|
        change(path, &mutation)
        assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.new(path) }
      end
    end
    with_data do |path|
      change(path) { |d| d["rnal"]["lisbon"]["count"] += 1 }
      assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.new(path) }
    end
  end

  def test_zero_distance_is_preserved_and_empty_population_is_supported
    with_data do |path|
      change(path) { |d| d["candidates"][0]["official_match"]["distance_km"] = 0 }
      assert_equal 0, AlojamentoLocal::CandidateDataset.new(path).candidates[0]["official_match"]["distance_km"]
      change(path) { |d| d["candidates"] = [] }
      data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
      assert_equal 13, data.dig("summary", "listing_count"), "Source totals must survive an empty candidate set"
      assert_equal 0, data.dig("summary", "candidate_count")
      change(path) do |d|
        d["listings"]["lisbon"]["count"] = 0
        d["listings"]["parishes"].each { |row| row["count"] = 0 }
      end
      data = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(path)).site_data
      assert_equal 0, data.dig("summary", "listing_count")
    end
  end
end
