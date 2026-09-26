require "minitest/autorun"
require_relative "../lib/al_ilegal"

class SpatialClustersTest < Minitest::Test
  def listing(lat, lng, name: "Apartment", room_type: "Entire home/apt", property_type: "Entire rental unit")
    {lat: lat, lng: lng, nome: name, room_type: room_type, property_type: property_type, licensa: "123"}
  end

  def test_groups_listings_within_half_a_kilometre
    listings = [listing(38.71, -9.14), listing(38.712, -9.14)]

    assert_equal 1, AlIlegal.spatial_clusters(listings).size
  end

  def test_separates_listings_in_different_locations
    listings = [listing(38.71, -9.14), listing(38.75, -9.14)]

    assert_equal 2, AlIlegal.spatial_clusters(listings).size
  end

  def test_distance_uses_farthest_pair_from_different_clusters_once_per_licence
    listings = [listing(38.71, -9.14), listing(38.7105, -9.14), listing(38.73, -9.14), listing(38.77, -9.14)]
    listings.each { |row| row[:license_group_assessment] = "licença repetida em várias localizações" }
    distance = AlIlegal.max_cross_cluster_distance_km(listings)
    expected = Haversine.distance(38.71, -9.14, 38.77, -9.14).to_km

    assert_in_delta expected, distance, 0.001
    assert_equal({"500_m_1_km" => 0, "1_2_km" => 0, "2_5_km" => 0, "over_5_km" => 1}, AlIlegal::Analysis.distance_range_counts(listings))
  end

  def test_distance_range_boundaries_do_not_overlap
    assert_raises(ArgumentError) { AlIlegal.distance_range_key(0.499) }
    assert_equal "500_m_1_km", AlIlegal.distance_range_key(0.5)
    assert_equal "1_2_km", AlIlegal.distance_range_key(1)
    assert_equal "2_5_km", AlIlegal.distance_range_key(2)
    assert_equal "2_5_km", AlIlegal.distance_range_key(5)
    assert_equal "over_5_km", AlIlegal.distance_range_key(5.001)
  end

  def test_identifies_room_level_listings_in_one_establishment
    listings = [
      listing(38.71, -9.14, name: "Room 1", room_type: "Private room"),
      listing(38.7105, -9.14, name: "Room 2", room_type: "Private room")
    ]

    assert_equal "provável estabelecimento com anúncios múltiplos", AlIlegal.license_group_assessment(
      listings, {"Concelho" => "Lisboa", "Modalidade" => "Apartamento"}
    )
  end

  def test_identifies_reuse_across_locations
    listings = [listing(38.71, -9.14), listing(38.75, -9.14)]

    assert_equal "licença repetida em várias localizações", AlIlegal.license_group_assessment(
      listings, {"Concelho" => "Lisboa", "Modalidade" => "Apartamento"}
    )
  end

  def test_does_not_call_a_single_listing_a_multi_listing_establishment
    assert_equal "licença única em Lisboa", AlIlegal.license_group_assessment(
      [listing(38.71, -9.14)], {"Concelho" => "Lisboa", "Modalidade" => "Apartamento"}
    )
  end

  def test_estimates_establishments_without_collapsing_suspicious_reuse
    likely = [listing(38.71, -9.14, name: "Room 1"), listing(38.7105, -9.14, name: "Room 2")]
    suspicious = [listing(38.71, -9.14), listing(38.75, -9.14)]
    suspicious.each { |item| item[:licensa] = "456" }
    likely.each { |item| item[:license_group_assessment] = "provável estabelecimento com anúncios múltiplos" }
    suspicious.each { |item| item[:license_group_assessment] = "licença repetida em várias localizações" }

    assert_equal 3, AlIlegal.establishment_estimate(likely + suspicious)
  end
end
