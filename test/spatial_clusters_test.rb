require "minitest/autorun"
require_relative "../lib/alojamento_local"

class SpatialClustersTest < Minitest::Test
  def listing(lat, lng, name: "Apartment", room_type: "Entire home/apt", property_type: "Entire rental unit")
    {lat: lat, lng: lng, nome: name, room_type: room_type, property_type: property_type, licensa: "123"}
  end

  def test_groups_listings_within_half_a_kilometre
    listings = [listing(38.71, -9.14), listing(38.712, -9.14)]

    assert_equal 1, AlojamentoLocal.spatial_clusters(listings).size
  end

  def test_separates_listings_in_different_locations
    listings = [listing(38.71, -9.14), listing(38.75, -9.14)]

    assert_equal 2, AlojamentoLocal.spatial_clusters(listings).size
  end

  def test_distance_uses_farthest_pair_from_different_clusters_once_per_licence
    listings = [listing(38.71, -9.14), listing(38.7105, -9.14), listing(38.73, -9.14), listing(38.77, -9.14)]
    listings.each { |row| row[:license_group_assessment] = "licença repetida em várias localizações" }
    distance = AlojamentoLocal.max_cross_cluster_distance_km(listings)
    expected = Haversine.distance(38.71, -9.14, 38.77, -9.14).to_km

    assert_in_delta expected, distance, 0.001
    assert_equal({"500_m_1_km" => 0, "1_2_km" => 0, "2_5_km" => 0, "over_5_km" => 1}, AlojamentoLocal::Analysis::History.distance_range_counts(listings))
  end

  def test_distance_range_boundaries_do_not_overlap
    assert_raises(ArgumentError) { AlojamentoLocal.distance_range_key(0.499) }
    assert_equal "500_m_1_km", AlojamentoLocal.distance_range_key(0.5)
    assert_equal "1_2_km", AlojamentoLocal.distance_range_key(1)
    assert_equal "2_5_km", AlojamentoLocal.distance_range_key(2)
    assert_equal "2_5_km", AlojamentoLocal.distance_range_key(5)
    assert_equal "over_5_km", AlojamentoLocal.distance_range_key(5.001)
  end

  def test_identifies_room_level_listings_in_one_establishment
    listings = [
      listing(38.71, -9.14, name: "Room 1", room_type: "Private room"),
      listing(38.7105, -9.14, name: "Room 2", room_type: "Private room")
    ]

    assert_equal "provável estabelecimento com anúncios múltiplos", AlojamentoLocal.license_group_assessment(
      listings, {"Concelho" => "Lisboa", "Modalidade" => "Apartamento"}
    )
  end

  def test_identifies_reuse_across_locations
    listings = [listing(38.71, -9.14), listing(38.75, -9.14)]

    assert_equal "licença repetida em várias localizações", AlojamentoLocal.license_group_assessment(
      listings, {"Concelho" => "Lisboa", "Modalidade" => "Apartamento"}
    )
  end

  def test_does_not_call_a_single_listing_a_multi_listing_establishment
    assert_equal "licença única em Lisboa", AlojamentoLocal.license_group_assessment(
      [listing(38.71, -9.14)], {"Concelho" => "Lisboa", "Modalidade" => "Apartamento"}
    )
  end

  def test_estimates_establishments_without_collapsing_suspicious_reuse
    likely = [listing(38.71, -9.14, name: "Room 1"), listing(38.7105, -9.14, name: "Room 2")]
    suspicious = [listing(38.71, -9.14), listing(38.75, -9.14)]
    suspicious.each { |item| item[:licensa] = "456" }
    likely.each { |item| item[:license_group_assessment] = "provável estabelecimento com anúncios múltiplos" }
    suspicious.each { |item| item[:license_group_assessment] = "licença repetida em várias localizações" }

    assert_equal 3, AlojamentoLocal.establishment_estimate(likely + suspicious)
  end
end

class SpatialClustersTest
  def test_transitive_bridge_is_order_independent_and_not_a_diameter_limit
    chain = [listing(38.71,-9.14), listing(38.714,-9.14), listing(38.718,-9.14)]
    chain.permutation.each { |rows| assert_equal 1, AlojamentoLocal.spatial_clusters(rows).size }
    assert_operator Haversine.distance(38.71,-9.14,38.718,-9.14).to_km, :>, 0.5
  end

  def test_missing_coordinates_are_not_zero_locations_and_cannot_collapse
    rows = [listing(nil,nil), listing(nil,nil)]
    assert_equal 2, AlojamentoLocal.spatial_clusters(rows).size
    assessment = AlojamentoLocal.license_group_assessment(rows, {"Concelho" => "Lisboa"})
    assert_equal "localização observada não identificada", assessment
    rows.each { |row| row[:license_group_assessment] = assessment }
    assert_equal 2, AlojamentoLocal.establishment_estimate(rows)
  end

  def test_priority_and_host_metadata_do_not_conflate_unmatched_with_lisbon
    near = [listing(38.71,-9.14), listing(38.7101,-9.14)]
    near.each_with_index { |row,i| row[:host_id] = i }
    assert_equal "provável estabelecimento com anúncios múltiplos", AlojamentoLocal.license_group_assessment(near, {"Concelho" => "Lisboa"})
    assert_equal "número sem correspondência no RNAL", AlojamentoLocal.license_group_assessment(near, nil)
    assert_equal "geografia oficial não identificada", AlojamentoLocal.license_group_assessment(near, {"Concelho" => nil})
    far = [listing(38.71,-9.14), listing(38.75,-9.14)]
    far.each { |row| row[:host_id] = "same" }
    assert_equal "licença repetida em várias localizações", AlojamentoLocal.license_group_assessment(far, nil)
    assert_equal "licença oficial fora de Lisboa", AlojamentoLocal.license_group_assessment(far, {"Concelho" => "Porto"})
    near.each { |row| row[:license_group_assessment] = AlojamentoLocal.license_group_assessment(near, nil) }
    assert_equal 2, AlojamentoLocal.establishment_estimate(near)
  end
end

class SpatialClustersTest
  def test_clustering_distance_threshold_is_inclusive
    rows = [listing(38.71,-9.14), listing(38.72,-9.14)]
    distance = Haversine.distance(38.71,-9.14,38.72,-9.14).to_km
    assert_equal 1, AlojamentoLocal.spatial_clusters(rows, threshold_km: distance).size
    assert_equal 2, AlojamentoLocal.spatial_clusters(rows, threshold_km: distance - 1e-9).size
  end

  def test_same_location_without_room_terms_remains_a_separate_lower_risk_category
    rows = [listing(38.71,-9.14,name: "Place A",property_type: "House"), listing(38.7101,-9.14,name: "Place B",property_type: "House")]
    assessment = AlojamentoLocal.license_group_assessment(rows, {"Concelho" => "Lisboa", "Modalidade" => "Apartamento"})
    assert_equal "licença repetida na mesma localização", assessment
    rows.each { |row| row[:license_group_assessment] = assessment }
    assert_equal 1, AlojamentoLocal.establishment_estimate(rows)
  end
end
