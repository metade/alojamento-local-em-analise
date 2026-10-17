require "minitest/autorun"
require "minitest/mock"
require_relative "../lib/alojamento_local"

class GroupingTest < Minitest::Test
  Grouping = AlojamentoLocal::Analysis::Grouping
  Entry = AlojamentoLocal::Analysis::DataSource::Entry
  DESCRIPTION = (1..40).map { |i| "token#{i}" }.join(" ")

  def entry(id, lat: 38.73, lng: -9.14, **changes)
    raw = {"id" => id.to_s, "host_id" => "1", "name" => "Lisbon lovely central room",
           "description" => DESCRIPTION, "room_type" => "Private room", "property_type" => "Room in rental unit", "bedrooms" => "1"}.merge(changes.transform_keys(&:to_s))
    Entry.new(raw: raw, coordinates: (lat && lng) ? [lat, lng] : nil)
  end

  def pair(a, b) = Grouping.new("123", [a, b]).assessments.first

  def test_thresholds_missing_evidence_and_host_differences
    a = entry(1)
    same = pair(a, entry(2))
    assert_equal [9, "merge"], same.values_at("score", "outcome")
    assert_equal [8, "merge"], pair(a, entry(2, host_id: "2")).values_at("score", "outcome")
    assert_equal [6, "review"], pair(a, entry(2, description: nil)).values_at("score", "outcome")
    assert_equal [3, "separate"], pair(entry(1, name: nil, description: nil, host_id: nil), entry(2)).values_at("score", "outcome")
    assert_equal [6, "review"], pair(a, entry(2, lat: nil)).values_at("score", "outcome")
    assert_equal "review", pair(a, entry(2, room_type: nil))["outcome"]
    assert_equal "separate", pair(a, entry(2, lat: 38.732))["outcome"]
    assert_equal "separate", pair(a, entry(2, room_type: "Entire home/apt"))["outcome"]
  end

  def test_distance_score_boundaries
    a = entry(1)
    [0.05, 0.050001, 0.1, 0.100001].zip([9, 8, 8, 6], %w[merge merge merge separate]).each do |distance, score, outcome|
      Grouping.stub(:distance, distance) do
        assert_equal [score, outcome], pair(a, entry(2)).values_at("score", "outcome")
      end
    end
  end

  def test_bedroom_contradiction_applies_to_entire_apartments_and_not_rooms
    assert_equal "merge", pair(entry(1), entry(2, bedrooms: "3"))["outcome"]
    a = entry(1, room_type: "Entire home/apt", property_type: "Entire rental unit")
    assert_equal "separate", pair(a, entry(2, room_type: "Entire home/apt", property_type: "Entire apartment", bedrooms: "2"))["outcome"]
    assert_equal "merge", pair(a, entry(2, room_type: "Entire home/apt", property_type: "Entire apartment", bedrooms: ""))["outcome"]
  end

  def test_text_normalization_preserves_numbers_and_requires_enough_tokens
    a = entry(1, name: "LISBON &amp; lovely central room 1")
    b = entry(2, name: "Lisbon & lovely central room 1")
    assert_includes pair(a, b)["reasons"], "similar_title"
    assert_includes pair(entry(1, name: "S&atilde;o&nbsp;Jos&eacute; quarto 1"), entry(2, name: "São José quarto 1"))["reasons"], "similar_title"
    refute_includes pair(entry(1, name: "Room 1"), entry(2, name: "Room 1"))["reasons"], "similar_title"
    refute_includes pair(entry(1, name: "Room 1 2"), entry(2, name: "Room 3 4"))["reasons"], "similar_title"
    refute_includes pair(entry(1, description: (1..29).map { |i| "t#{i}" }.join(" ")), entry(2))["reasons"], "strong_description"
    refute_includes pair(entry(1, description: "repeat " * 50), entry(2, description: "repeat " * 50))["reasons"], "strong_description"
  end

  def test_exact_text_similarity_thresholds
    a = entry(1, name: "one two three four")
    assert_includes pair(a, entry(2, name: "one two three five six"))["reasons"], "similar_title"
    refute_includes pair(a, entry(2, name: "one two three five six seven"))["reasons"], "similar_title"
    common = (1..32).map { |i| "common#{i}" }
    first = (common + %w[first1 first2 first3 first4]).join(" ")
    second = (common + %w[second1 second2 second3 second4]).join(" ")
    assert_includes pair(entry(1, description: first), entry(2, description: second))["reasons"], "strong_description"
    refute_includes pair(entry(1, description: first), entry(2, description: second.sub("common32", "extra")))["reasons"], "strong_description"
  end

  def test_complete_link_chain_and_deterministic_tie
    entries = [entry(1, lat: 38.73), entry(2, lat: 38.7308), entry(3, lat: 38.7316)]
    first = Grouping.new("123", entries)
    assert_equal [%w[1 2], %w[3]], first.groups.map { |g| g.map { |e| e.raw["id"] } }
    leftover = first.assessments.find { |p| p["listing_ids"] == %w[2 3] }
    assert_equal "review", leftover["outcome"]
    assert_includes leftover["reasons"], "complete_link_conflict"
    second = Grouping.new("123", entries.reverse)
    assert_equal first.groups, second.groups
    assert_equal first.assessments, second.assessments
    # Middle member minimizes total distance; missing locations contribute no invented distance.
    assert_equal entries[1].coordinates, Grouping.medoid(entries + [entry(4, lat: nil)])
    assert_equal entries[0].coordinates, Grouping.medoid(entries.take(2))
  end
end
