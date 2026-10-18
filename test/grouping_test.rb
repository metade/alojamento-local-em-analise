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
    Entry.new(raw: raw, declaration: AlojamentoLocal::Analysis::Declaration.new(raw.fetch("license", "123/AL")), coordinates: (lat && lng) ? [lat, lng] : nil)
  end

  def pair(a, b, official_records: {}) = Grouping.new([a, b], official_records: official_records).assessments.first

  def test_merge_eligibility_by_same_and_different_hosts
    assert_equal [9, "merge"], pair(entry(1), entry(2)).values_at("score", "outcome")
    assert_equal [8, "merge"], pair(entry(1), entry(2, host_id: "2")).values_at("score", "outcome")
    assert_equal "review", pair(entry(1), entry(2, description: nil))["outcome"]
    assert_equal "review", pair(entry(1), entry(2, lat: nil))["outcome"]
    assert_equal "merge", pair(entry(1), entry(2, room_type: nil))["outcome"]
  end

  def test_relationship_is_undetermined_without_specific_duplicate_evidence
    assert_equal ["merge", "undetermined"], pair(entry(1), entry(2)).values_at("outcome", "relationship")
    assert_equal "undetermined", pair(entry(1), entry(2, description: nil))["relationship"]
    assert_equal "undetermined", pair(entry(1), entry(2, lat: 39.0))["relationship"]
    assert_equal "undetermined", pair(entry(1), entry(2, room_type: nil))["relationship"]
    assert_equal "undetermined", pair(entry(1), entry(2, license: "999/AL"))["relationship"]
    a = entry(1, room_type: "Entire home/apt")
    assert_equal "duplicate_adverts", pair(a, entry(2, room_type: "Entire home/apt"))["relationship"]
    assert_equal "undetermined", pair(a, entry(2, room_type: "Entire home/apt", bedrooms: "2"))["relationship"]
    assert_equal "undetermined", pair(a, entry(2, room_type: "Entire home/apt", lat: nil))["relationship"]
    room = pair(entry(1, name: "Central bright lovely room 1"), entry(2, name: "Central bright lovely room 1", host_id: "2"))
    assert_equal ["merge", "duplicate_adverts"], room.values_at("outcome", "relationship")
    assert_equal 8, room["score"]
    assert_includes room["reasons"], "same_room_reference"
    unit_only = pair(entry(1, name: "Central apartment B bright"), entry(2, name: "Central apartment B bright"))
    assert_equal ["merge", "undetermined"], unit_only.values_at("outcome", "relationship")
  end

  def apartment_record(**changes)
    {"municipality" => "Lisboa", "type" => "Apartamento", "coordinates" => [38.73, -9.14]}.merge(changes.transform_keys(&:to_s))
  end

  def test_distinct_locally_registered_apartments_resolve_a_review_without_merging
    a = entry(1, room_type: "Entire home/apt", property_type: "Entire rental unit", license: "100/AL")
    b = entry(2, room_type: "Entire home/apt", property_type: "Entire rental unit", license: "200/AL")
    records = {"100" => apartment_record, "200" => apartment_record}
    unresolved = pair(a, b)
    resolved = pair(a, b, official_records: records)
    assert_equal [7, "separate", "separate_apartments"], resolved.values_at("score", "outcome", "relationship")
    assert_equal unresolved["score"], resolved["score"]
    assert_includes resolved["reasons"], "conflicting_al_numbers"
    assert_includes resolved["reasons"], "distinct_registered_apartments"
    refute_includes resolved["reasons"], "review_score"
    grouping = Grouping.new([a, b], official_records: records)
    assert_equal [%w[1], %w[2]], grouping.groups.map { |group| group.map { |entry| entry.raw["id"] } }
    assert_equal grouping.assessments, Grouping.new([b, a], official_records: records).assessments
    # Missing/conflicting national fields, nonlocal records and different accommodation types stay unresolved.
    [{}, {"100" => apartment_record}, *[
      {coordinates: nil}, {coordinates: [41.15, -8.61]}, {municipality: nil},
      {municipality: "Porto"}, {type: nil}, {type: "Moradia"}
    ].map { |changes| records.merge("200" => apartment_record(**changes)) }].each do |uncertain|
      assert_equal "review", pair(a, b, official_records: uncertain)["outcome"]
    end
    [
      entry(2, room_type: "Private room", license: "200/AL"),
      entry(2, room_type: "Entire home/apt", property_type: "Entire rental unit", license: "200/AL", lat: nil),
      entry(2, room_type: "Entire home/apt", property_type: "Entire rental unit", license: "200/AL", lat: 38.736),
      entry(2, room_type: "Entire home/apt", property_type: nil, license: "200/AL"),
      entry(2, room_type: "Entire home/apt", property_type: "Entire rental unit", license: "200/AL e 300/AL"),
      entry(2, room_type: "Entire home/apt", property_type: "Entire rental unit", license: "200/AL plus unsupported text")
    ].each do |uncertain|
      refute_equal "separate", pair(a, uncertain, official_records: records)&.fetch("outcome")
    end
    shared_unit = [a, b].map.with_index do |original, index|
      entry(index + 1, **original.raw.except("id").merge("name" => "Lovely central apartment B"))
    end
    assert_equal "review", pair(*shared_unit, official_records: records)["outcome"]
    assert_equal "review", pair(entry(1, license: "100/AL"), entry(2, license: "200/AL"), official_records: records)["outcome"]
    same_number = entry(2, room_type: "Entire home/apt", property_type: "Entire rental unit", license: "100/AL")
    assert_equal "merge", pair(a, same_number, official_records: records)["outcome"]
    assert_equal pair(a, same_number), pair(a, same_number, official_records: records)
  end

  def test_search_radius_and_displaced_coordinates
    a = entry(1)
    [0.5, 0.500001].zip([9, 8], %w[merge review]).each do |distance, score, outcome|
      Grouping.stub(:distance, distance) do
        assert_equal [score, outcome], pair(a, entry(2)).values_at("score", "outcome")
      end
    end
    assert_equal "review", pair(a, entry(2, lat: 39.0))["outcome"]
  end

  def test_entire_apartment_attributes_contradict_but_room_attributes_do_not
    %w[bedrooms beds bathrooms accommodates].each do |key|
      assert_equal "merge", pair(entry(1, **{key => "1"}), entry(2, **{key => "3"}))["outcome"]
      a = entry(1, room_type: "Entire home/apt", **{key => "1"})
      assert_equal "review", pair(a, entry(2, room_type: "Entire home/apt", **{key => "3"}))["outcome"]
      assert_equal "merge", pair(a, entry(2, room_type: "Entire home/apt", **{key => "bad"}))["outcome"]
    end
    assert_equal "review", pair(entry(1, room_type: "Entire home/apt"), entry(2, room_type: "Entire home/apt", property_type: "Entire house"))["outcome"]
    assert_equal "review", pair(entry(1, room_type: "Entire home/apt", property_type: "Entire rental unit"), entry(2, room_type: "Entire home/apt", property_type: "Entire loft"))["outcome"]
    assert_equal "merge", pair(entry(1, room_type: "Entire home/apt", property_type: "Entire rental unit"), entry(2, room_type: "Entire home/apt", property_type: "Entire apartment"))["outcome"]
  end

  def test_unit_and_room_references_and_cross_category_relationships
    a = entry(1, name: "Lovely apartment 7 room 1 central")
    b = entry(2, name: "Lovely apartment 7 room 2 central", room_type: "Shared room")
    assert_equal ["merge", "separate_rooms"], pair(a, b).values_at("outcome", "relationship")
    b.raw["room_type"] = "Entire home/apt"
    assert_equal ["merge", "apartment_and_rooms"], pair(a, b).values_at("outcome", "relationship")
    assert_equal "review", pair(entry(1), entry(2, room_type: "Shared room"))["outcome"]
    same_category_rooms = [entry(1, name: "Central bright lovely room 1"), entry(2, name: "Central bright lovely room 2")]
    assert_equal ["merge", "separate_rooms"], pair(*same_category_rooms).values_at("outcome", "relationship")
    refute_includes pair(*same_category_rooms)["reasons"], "same_apartment_reference"
    beds = [entry(1, name: "Central apartment 7 bed 1", room_type: "Shared room"), entry(2, name: "Central apartment 7 bed 2", room_type: "Shared room")]
    assert_equal ["merge", "separate_rooms"], pair(*beds).values_at("outcome", "relationship")
    assert_equal "review", pair(a, entry(2, name: "Lovely apartment 8 room 2 central"))["outcome"]
    refute_includes pair(a, entry(2, name: "apartment 7 and apartment 8"))["reasons"], "same_apartment_reference"
    ["apartment a lovely central room", "apartment 2 bedrooms central room", "Stylish City Centre Apartments", "Cozy Room in Apt w/ Terrace", "Lovely apartmento central", "the apartment’s lovely terrace", "apartment. A spacious sunny place", "apartment <br />A very spacious room", "apartment\nA very spacious room", "apartment. I live here", "apartment T2 central sunny", "apartment 2 br in Alfama", "Apartment 6-8 persons", "Apartment 3rd floor central room", "Apartment 2br central room", "Apartment 3 floors central room", "Apartment 1-A central room", "Apartment 1.2 central room", "Apartment 1 & 2 central rooms", "apt w\\ balcony"].each do |title|
      refute_includes pair(entry(1, name: title), entry(2, name: title))["reasons"], "same_apartment_reference"
    end
    %w[AB12 12AB A1B2].each do |identifier|
      assert_includes pair(entry(1, name: "Central lovely apartment #{identifier}"), entry(2, name: "Central lovely apartment #{identifier}"))["reasons"], "same_apartment_reference"
    end
    refute_includes pair(entry(1, name: "Lovely central apartment", description: "A #{DESCRIPTION}"), entry(2, name: "Lovely central apartment", description: "A #{DESCRIPTION}"))["reasons"], "same_apartment_reference"
    %w[flat apartamento apt apt. unidade].each do |label|
      assert_includes pair(entry(1, name: "#{label} B central lovely"), entry(2, name: "#{label} B central lovely"))["reasons"], "same_apartment_reference"
    end
  end

  def test_unnumbered_and_conflicting_declarations
    assert_equal "merge", pair(entry(1, license: "999999999/AL"), entry(2, license: "999999999/AL"))["outcome"]
    a = entry(1, name: "Lovely apartment 7 central room", license: "123/AL")
    [nil, "Exempt", "unsupported"].each do |licence|
      assert_equal "merge", pair(a, entry(2, name: a.raw["name"], license: licence))["outcome"]
    end
    ["999/AL", "123/AL e 999/AL"].each do |licence|
      assert_equal "review", pair(a, entry(2, name: a.raw["name"], license: licence))["outcome"]
    end
    # No unit reference: generic host text and exemption/zero placeholders confer no identity.
    ["Exempt", "0/AL", nil].each do |licence|
      grouping = Grouping.new([entry(1, license: licence), entry(2, license: licence)])
      assert_equal 2, grouping.groups.size
    end
    assert_equal 1, Grouping.new([entry(1, name: a.raw["name"], license: nil), entry(2, name: a.raw["name"], license: "Exempt")]).groups.size
  end

  def test_spatial_discovery_crosses_cells_and_deduplicates_evidence
    a = entry(1, license: nil, name: "Lovely apartment 7 central room")
    b = entry(2, lat: 38.726, license: nil, name: a.raw["name"])
    grouping = Grouping.new([a, b])
    refute_equal grouping.send(:cell, a), grouping.send(:cell, b)
    assert_equal 1, grouping.assessments.size
    assert_equal 1, grouping.groups.size
    b.raw["name"] = "Lovely generic central room"
    a.raw["name"] = b.raw["name"]
    assert_equal "review", Grouping.new([a, b]).assessments.first["outcome"]
    assert_empty Grouping.new([a, entry(2, lat: 40, license: nil)]).assessments
  end

  def test_five_members_require_all_ten_qualifying_pairs
    grouping = Grouping.new((1..5).map { |id| entry(id) })
    assert_equal 1, grouping.groups.size
    assert_equal 10, grouping.assessments.count { |pair| pair["outcome"] == "merge" }
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

  def test_complete_link_prefers_the_highest_minimum_cross_pair_score
    entries = [entry(1, lat: 38.73, host_id: "a"), entry(2, lat: 38.734, host_id: "b"), entry(3, lat: 38.738, host_id: "b")]
    grouping = Grouping.new(entries)
    assert_equal [%w[1], %w[2 3]], grouping.groups.map { |group| group.map { |entry| entry.raw["id"] } }
    assert_equal grouping.assessments, Grouping.new(entries.shuffle(random: Random.new(17))).assessments
  end

  def test_complete_link_chain_and_deterministic_tie
    entries = [entry(1, lat: 38.73), entry(2, lat: 38.734), entry(3, lat: 38.738)]
    first = Grouping.new(entries)
    assert_equal [%w[1 2], %w[3]], first.groups.map { |g| g.map { |e| e.raw["id"] } }
    leftover = first.assessments.find { |p| p["listing_ids"] == %w[2 3] }
    assert_equal "review", leftover["outcome"]
    assert_includes leftover["reasons"], "complete_link_conflict"
    second = Grouping.new(entries.reverse)
    assert_equal first.groups, second.groups
    assert_equal first.assessments, second.assessments
    # Middle member minimizes total distance; missing locations contribute no invented distance.
    assert_equal entries[1].coordinates, Grouping.medoid(entries + [entry(4, lat: nil)])
    assert_equal entries[0].coordinates, Grouping.medoid(entries.take(2))
  end
end
