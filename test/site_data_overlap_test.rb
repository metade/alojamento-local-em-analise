require "minitest/autorun"
require_relative "../lib/alojamento_local"

class SiteDataOverlapTest < Minitest::Test
  def test_narrow_regions_use_leaders_and_broad_regions_keep_labels_inside
    geometry = AlojamentoLocal::SiteData::Overlap.geometry(11869, 8888, 7287)
    labels = AlojamentoLocal::SiteData::Overlap.labels(geometry, 4582, 7287, 1601)
    assert_equal [4582, 7287, 1601], labels.map { |label| label.fetch("count") }
    assert labels.first.fetch("callout")
    refute labels[1].fetch("callout")
    assert labels.last.fetch("callout")
    labels.each do |label|
      assert_operator label.fetch("target"), :>=, 0
      assert_operator label.fetch("target"), :<=, 640
    end
  end

  def test_labels_support_empty_disjoint_identical_and_contained_sets
    [[0,0,0], [0,80,0], [100,80,0], [100,100,100], [100,25,25], [25,100,25]].each do |a,b,i|
      geometry = AlojamentoLocal::SiteData::Overlap.geometry(a,b,i)
      labels = AlojamentoLocal::SiteData::Overlap.labels(geometry, a-i, i, b-i)
      assert_equal [a-i, i, b-i], labels.map { |label| label.fetch("count") }
      labels.each do |label|
        assert ["x", "y", "target"].all? { |key| label.fetch(key).finite? }
      end
      labels.select { |label| label.fetch("count").positive? && !label.fetch("callout") }.each do |label|
        x = label.fetch("x")
        inside_rnal = (x - geometry.fetch("x")).abs < geometry.fetch("r")
        inside_airbnb = (x - geometry.fetch("y")).abs < geometry.fetch("s")
        case label.fetch("key")
        when "rnal" then assert inside_rnal && !inside_airbnb
        when "common" then assert inside_rnal && inside_airbnb
        when "airbnb" then assert !inside_rnal && inside_airbnb
        end
      end
    end
  end

  def test_geometry_preserves_circle_and_overlap_area_ratios
    [[100,80,40], [0,80,0], [0,0,0], [100,80,0], [100,100,100], [100,25,25], [100,1,1], [25,100,25]].each do |a,b,i|
      g = AlojamentoLocal::SiteData::Overlap.geometry(a,b,i)
      assert g.values.all?(&:finite?)
      assert_operator g["x"] - g["r"], :>=, 19.999
      assert_operator g["y"] + g["s"], :<=, 620.001
      next if a.zero?
      assert_in_delta b.to_f/a, g["s"]**2 / g["r"]**2, 1e-6
      overlap = AlojamentoLocal::SiteData::Overlap.area(g["r"],g["s"],g["distance"])
      assert_in_delta i.to_f/a, overlap/(Math::PI*g["r"]**2), 1e-6
    end
    assert_raises(ArgumentError) { AlojamentoLocal::SiteData::Overlap.geometry(2,1,2) }
  end
end
