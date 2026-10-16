require "minitest/autorun"
require_relative "../lib/alojamento_local"

class SiteDataOverlapTest < Minitest::Test
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
