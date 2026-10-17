require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "support/candidate_fixture"

class CandidateDatasetTest < Minitest::Test
  def document = JSON.parse(JSON.generate(CandidateFixture.dataset.document))

  def data(doc = document) = AlojamentoLocal::SiteData.new(dataset: AlojamentoLocal::CandidateDataset.new(document: doc)).site_data

  def test_presentation_counts_and_many_to_many_accounting_are_preserved
    site = data
    assert_equal [12, 13, 7, 17], site["summary"].values_at("candidate_count", "listing_count", "distinct_al_numbers", "official_numbers")
    assert_equal [12, 8, 4, 9], site["metrics"].values_at("airbnb", "intersection", "airbnb_only", "rnal_only")
    assert site["metrics"]["geometry"]
    assert_equal 12, site["districts"].sum { |d| d["candidate_count"] } + site["unknown"]["candidate_count"]
    assert_equal 13, site["districts"].sum { |d| d["listing_count"] } + site["unknown"]["listing_count"]
    assert_equal 24, site["districts"].size
    arroios = site["districts"].find { |d| d["name"] == "Arroios" }
    assert_equal [5, 8, 4], arroios.values_at("candidate_count", "listing_count", "distinct_al_numbers")
    assert_equal 2, site["candidates"].count { |c| c["listing_ids"].include?("demo-105") }
    assert_equal "belm", site["districts"].find { |d| d["name"] == "Belém" }["slug"]
    assert_equal [2, 1, 1], site["signals"].values_at("unidentified_licence_listings", "empty_licence_listings", "unrecognised_licence_listings")
    assert_equal 2, site["signals"]["repeated_listings"]
    assert_equal 1, site["distance_total"]
    assert_equal [0, 0, 0, 0, 1], site["distance_ranges"].map { |r| r["count"] }
    assert_equal [{"name" => "Algarve", "count" => 1, "unresolved" => false, "width" => 100.0}], site.dig("outside_regions", "rows")
  end

  def test_report_only_omits_resolved_unflagged_matches
    doc = document
    candidate = doc["candidates"].first
    candidate["official_match"]["distance_km"] = 0.5
    site = data(doc)
    refute_includes site["report_candidates"].map { |row| row["id"] }, candidate["id"]
    assert_equal 12, site["candidates"].size
    assert_equal 12, site.dig("summary", "candidate_count")
    [
      ->(c) { c["signals"] = ["partial_licence_extraction"] },
      ->(c) { c["official_match"]["distance_km"] = nil },
      ->(c) { c["official_match"]["distance_km"] = 0.5001 },
      ->(c) { c["official_match"]["freguesia"] = nil },
      ->(c) { c["official_match"]["freguesia"] = "Belém" },
      ->(c) { c["official_match"]["municipality"] = nil },
      ->(c) { c["geography"]["coordinate_freguesia"] = nil },
      ->(c) { c["freguesia"] = nil }
    ].each do |mutation|
      changed = JSON.parse(JSON.generate(doc))
      mutation.call(changed["candidates"].first)
      assert_includes data(changed)["report_candidates"].map { |row| row["id"] }, candidate["id"]
    end
  end

  def test_numbered_candidates_exceeding_rnal_keep_counts_without_invalid_geometry
    doc = document
    doc["rnal"]["lisbon"]["count"] = 0
    doc["rnal"]["parishes"].each { |row| row["count"] = 0 }
    metrics = data(doc)["metrics"]
    assert_equal [12, 8, 4], metrics.values_at("airbnb", "intersection", "airbnb_only")
    assert_nil metrics["geometry"]
  end

  def test_distance_boundaries_zero_and_explicitly_unresolved_matches
    doc = document
    [[0, 0], [0.5, 0], [0.5001, 1], [1, 1], [1.0001, 2], [2, 2], [2.0001, 3], [5, 3], [5.0001, 4]].each do |distance, index|
      doc["candidates"].select { |c| c["al_number"] == "100005" }.each { |c| c["official_match"]["distance_km"] = distance }
      rows = data(doc)["distance_ranges"]
      assert_equal 1, rows[index]["count"]
      assert_equal 1, rows.sum { |r| r["count"] }
    end
    doc["candidates"].find { |c| c["al_number"] == "100005" }["official_match"]["distance_km"] = nil
    assert_equal({"label" => "Distância por resolver", "count" => 1, "unresolved" => true, "width" => 100.0}, data(doc)["distance_ranges"].last)
  end

  def test_source_dates_allow_unknown_fetch_but_require_a_valid_archive_date
    doc = document
    assert_equal "2024-06-01", data(doc)["source_dates"]["airbnb_snapshot_date"]
    %w[airbnb_fetched_on rnal_fetched_on].each { |key| doc["source_dates"][key] = nil }
    AlojamentoLocal::CandidateDataset.validate!(doc)
    [nil, "2024-02-30", "01/07/2024"].each do |date|
      invalid = document
      invalid["source_dates"]["airbnb_snapshot_date"] = date
      assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.validate!(invalid) }
    end
  end

  def test_strict_schema_privacy_and_accounting_failures
    mutations = [
      ->(d) { d["candidates"].first["address"] = "private" },
      ->(d) { d["candidates"].first["official_match"]["latitude"] = 38.7 },
      ->(d) { d["host_id"] = "private" },
      ->(d) { d["candidates"].first["listing_count"] = 99 },
      ->(d) { d["candidates"].first["listing_ids"] *= 2 },
      ->(d) { d["candidates"].first["id"] = d["candidates"][1]["id"] },
      ->(d) { d["candidates"].first["raw_licences"] = {} },
      ->(d) { d["candidates"].first["raw_licences"].transform_values! { "999/AL" } },
      ->(d) { d["candidates"].first["registration_status"] = "exempt" },
      ->(d) { d["candidates"].first["official_match"] = nil },
      ->(d) { d["candidates"].first["official_match"]["distance_km"] = -1 },
      ->(d) { d["candidates"].first["signals"] = ["invented"] },
      ->(d) { d["listings"]["lisbon"]["count"] += 1 },
      ->(d) { d["listings"]["parishes"].first["count"] += 1 },
      ->(d) { d["rnal"]["lisbon"]["count"] += 1 },
      ->(d) { d["candidates"] = [] },
      ->(d) { d["grouping_assessments"] = [] },
      ->(d) { d["grouping_assessments"] << d["grouping_assessments"].first },
      ->(d) { d["grouping_assessments"].first["listing_ids"] = %w[demo-101 demo-102] },
      ->(d) { d["grouping_assessments"].first["outcome"] = "separate" },
      ->(d) { d["grouping_assessments"].first["score"] = 6 }
    ]
    mutations.each_with_index do |mutation, index|
      doc = document
      mutation.call(doc)
      assert_raises(ArgumentError, "mutation #{index}") { AlojamentoLocal::CandidateDataset.validate!(doc) }
    end
  end

  def test_unnumbered_contributions_cannot_merge_or_duplicate
    [false, true].each do |merge|
      doc = document
      candidate = doc["candidates"].find { |c| c["registration_status"] == "exempt" }
      other = doc["candidates"].reverse.find { |c| c["registration_status"] == "exempt" }
      if merge
        candidate["listing_ids"] += other["listing_ids"]
        candidate["raw_licences"].merge!(other["raw_licences"])
        candidate["listing_count"] = 2
        candidate["grouping_reason"] = "scored_merge"
        doc["candidates"].delete(other)
      else
        doc["candidates"] << candidate.merge("id" => "duplicate-unnumbered-contribution")
      end
      assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.validate!(doc) }
    end
  end

  def test_empty_population_and_nonadditive_rnal_are_supported
    doc = document
    doc["candidates"] = []
    doc["grouping_assessments"] = []
    doc["listings"]["lisbon"]["count"] = 0
    doc["listings"]["parishes"].each { |row| row["count"] = 0 }
    doc["rnal"]["lisbon"]["count"] = 1
    doc["rnal"]["parishes"].each { |row| row["count"] = %w[Arroios Estrela].include?(row["freguesia"]) ? 1 : 0 }
    site = data(doc)
    assert_equal [0, 0], site["summary"].values_at("listing_count", "candidate_count")
    assert_empty site["distance_ranges"]
    assert_empty site["outside_regions"]["rows"]
  end

  def test_latest_dated_directory_is_selected_without_fallback
    Dir.mktmpdir do |root|
      older = File.join(root, "2024-06-01__2024-07-01")
      latest = File.join(root, "2024-07-01__2024-08-01")
      FileUtils.mkdir_p([older, latest])
      FileUtils.cp(File.join(CandidateFixture::PATH, "snapshot.json"), older)
      assert_equal latest, AlojamentoLocal::CandidateDataset.default_path(root: root)
      assert_raises(Errno::ENOENT) { AlojamentoLocal::CandidateDataset.new(AlojamentoLocal::CandidateDataset.default_path(root: root)) }
      File.write(File.join(latest, "snapshot.json"), "{}")
      assert_raises(ArgumentError) { AlojamentoLocal::CandidateDataset.new(latest) }
    end
  end
end
