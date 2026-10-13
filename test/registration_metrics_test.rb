require "minitest/autorun"
require "tmpdir"
require_relative "../lib/alojamento_local"

class RegistrationMetricsTest < Minitest::Test
  def observed(number, parish, raw: number)
    {licensa: AlojamentoLocal.parse_al_license(number), licensa_raw: raw, bairro: AlojamentoLocal::Geography.parish(parish)}
  end

  def test_sets_are_distinct_and_local_with_exhaustive_differences
    Dir.mktmpdir do |dir|
      path = File.join(dir, "official.csv")
      CSV.open(path, "w", write_headers: true, headers: %w[NrRNAL Concelho Freguesia]) do |csv|
        csv << ["001", " Lisboa ", "ARROIOS"]
        csv << ["1", "Lisboa", "Arroios"] # duplicate entry
        csv << ["2", "Lisboa", "Belém"]
        csv << ["3", "Porto", "Bonfim"]
        csv << ["4", nil, nil]
        csv << ["5", "Lisboa", "Unknown"]
        csv << ["6", "Lisboa", "Arroios"] # RNAL-only in Arroios; observed elsewhere
        csv << ["7", "Lisboa", "Arroios"] # conflicting official geography
        csv << ["7", "Porto", "Bonfim"]
        csv << ["n/a", "Lisboa", nil]
      end
      listings = [observed("1/AL", "Arroios"), observed("001/AL", "Arroios"), observed("1", "Belm"),
                  *%w[2 3 4 5 8].map { |n| observed(n, "Arroios") }, observed("6", "Belém"),
                  observed("7", "Belém"), observed(nil, "Arroios", raw: " "), observed("406/UT/2017", "Arroios"),
                  observed("1", "missing")]
      metrics = AlojamentoLocal::Analysis::RegistrationMetrics.calculate(listings, path)
      city = metrics[:rows].first
      arroios = metrics[:rows].find { |row| row[:geography] == "Arroios" }
      belem = metrics[:rows].find { |row| row[:geography] == "Belém" }
      assert_equal [5,8,5,0,3], city.values_at(:rnal,:airbnb,:intersection,:rnal_only,:airbnb_only)
      assert_equal [1,1,1], city.values_at(:another_municipality,:no_national_match,:unresolved_official_geography)
      assert_equal [3,6,1,2,5], arroios.values_at(:rnal,:airbnb,:intersection,:rnal_only,:airbnb_only)
      assert_equal [1,1,1,2], arroios.values_at(:another_lisbon_parish,:another_municipality,:no_national_match,:unresolved_official_geography)
      assert_equal 2, belem[:another_lisbon_parish]
      assert_equal 1, belem[:unresolved_official_geography]
      assert_operator metrics[:rows].drop(1).sum { |r| r[:airbnb] }, :>, city[:airbnb]
      assert_equal [13,1,1,11,10], city.values_at(:announcements,:empty_licence,:unrecognised_licence,:identifiable_number,:confirmed_rnal_match)
      assert_equal 1, metrics[:diagnostics][:unparseable_official_numbers]
      assert_equal 2, metrics[:diagnostics][:duplicate_number_extra_entries]
      assert_equal 2, metrics[:diagnostics][:lisbon_entries_unresolved_parish]
      assert_equal 0, metrics[:rows].last[:intersection]
    end
  end

  def test_same_path_with_different_bytes_cannot_reuse_official_cache
    Dir.mktmpdir do |dir|
      path = File.join(dir, "official.csv")
      File.write(path, "NrRNAL,Concelho\n00123,Lisboa\n")
      assert AlojamentoLocal.licensed_als(path).key?("123")
      File.write(path, "NrRNAL,Concelho\n456,Porto\n")
      refute AlojamentoLocal.licensed_als(path).key?("123")
      assert AlojamentoLocal.licensed_als(path).key?("456")
    end
  end

  def test_geometry_preserves_circle_and_overlap_area_ratios
    [[100,80,40], [0,80,0], [0,0,0], [100,80,0], [100,100,100], [100,25,25], [100,1,1], [25,100,25]].each do |a,b,i|
      g = AlojamentoLocal::Overlap.geometry(a,b,i)
      assert g.values.all?(&:finite?)
      assert_operator g["x"] - g["r"], :>=, 19.999
      assert_operator g["y"] + g["s"], :<=, 620.001
      next if a.zero?
      assert_in_delta b.to_f/a, g["s"]**2 / g["r"]**2, 1e-6
      overlap = AlojamentoLocal::Overlap.area(g["r"],g["s"],g["distance"])
      assert_in_delta i.to_f/a, overlap/(Math::PI*g["r"]**2), 1e-6
    end
    assert_raises(ArgumentError) { AlojamentoLocal::Overlap.geometry(2,1,2) }
  end

  def test_invalid_accounting_is_rejected
    Dir.mktmpdir do |dir|
      path = File.join(dir, "empty.csv")
      File.write(path, "NrRNAL,Concelho,Freguesia\n")
      metrics = AlojamentoLocal::Analysis::RegistrationMetrics.calculate([], path)
      metrics[:rows].first[:intersection] = 1
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::RegistrationMetrics.validate!(metrics) }
    end
  end
end
