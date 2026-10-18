require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "digest"
require_relative "support/pipeline_fixture"

class BoundariesTest < Minitest::Test
  def test_full_resolution_cml_polygons_and_known_points
    boundaries = AlojamentoLocal::Analysis::Boundaries.new
    assert_equal "Arroios", boundaries.parish([38.73, -9.14])
    assert_nil boundaries.parish([0, 0])
    assert_nil boundaries.parish(nil)
    doc = JSON.parse(File.read(AlojamentoLocal::Analysis::Boundaries::PATH))
    assert_equal AlojamentoLocal::Geography::PARISHES.sort, doc["features"].map { |f| f["freguesia"] }.sort
    assert_match(/\A[a-f0-9]{64}\z/, doc.dig("source", "original_sha256"))
    assert_equal 29574, doc["features"].sum { |f| f["geometry"]["coordinates"].flatten.size }, "Full-resolution analytical polygons must retain the supplied vertices"
  end

  def test_analytical_derivative_preserves_the_committed_original
    path = File.expand_path("../data_sources/lisboa-freguesias.geojson", __dir__)
    original = JSON.parse(File.read(path))
    derivative = JSON.parse(File.read(AlojamentoLocal::Analysis::Boundaries::PATH))
    assert_equal Digest::SHA256.file(path).hexdigest, derivative.dig("source", "original_sha256")
    expected = original.fetch("features").to_h { |feature| [feature.dig("properties", "NOME"), feature.fetch("geometry")] }
    actual = derivative.fetch("features").to_h { |feature| [feature.fetch("freguesia"), feature.fetch("geometry")] }
    assert_equal expected, actual
  end

  def test_holes_multipolygons_and_overlapping_boundaries
    Dir.mktmpdir do |root|
      square = [[0, 0], [4, 0], [4, 4], [0, 4], [0, 0]]
      hole = [[1, 1], [2, 1], [2, 2], [1, 2], [1, 1]]
      other = [[4, 0], [5, 0], [5, 4], [4, 4], [4, 0]]
      features = [{"freguesia" => "Arroios", "geometry" => {"type" => "Polygon", "coordinates" => [square, hole]}},
        {"freguesia" => "Belém", "geometry" => {"type" => "MultiPolygon", "coordinates" => [[other]]}}]
      path = File.join(root, "polygons.json")
      File.write(path, JSON.generate("features" => features))
      boundaries = AlojamentoLocal::Analysis::Boundaries.new(path)
      assert_equal "Arroios", boundaries.parish([3, 3])
      assert_nil boundaries.parish([1.5, 1.5])
      assert_equal "Belém", boundaries.parish([2, 4.5])
      assert_nil boundaries.parish([2, 4]), "Shared polygon edges remain unresolved"
    end
  end

  def test_airbnb_assignment_is_not_overridden_and_requires_member_unanimity
    PipelineFixture.with_sources do |_, airbnb, official|
      fake = Object.new
      def fake.parish(_) = "Belém"

      AlojamentoLocal::Analysis::Boundaries.stub(:new, fake) do
        pair = PipelineFixture.pair(airbnb, official)
        dataset = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: pair).build
        merged = dataset.candidates.find { |c| c["listing_ids"] == %w[1 2] }
        assert_equal "Arroios", merged["freguesia"]
        assert_equal "Belém", merged["geography"]["coordinate_freguesia"]
        assert_includes merged["signals"], "observed_parish_disagreement"
        table = CSV.read(airbnb, headers: true)
        table.find { |row| row["id"] == "2" }["neighbourhood_cleansed"] = "Belém"
        CSV.open(airbnb, "w") { |csv|
          csv << table.headers
          table.each { |row| csv << row.fields }
        }
        File.delete("#{airbnb}.manifest.json")
        dataset = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: PipelineFixture.pair(airbnb, official)).build
        merged = dataset.candidates.find { |c| c["listing_ids"] == %w[1 2] }
        assert_nil merged["freguesia"]
        assert_equal %w[Arroios Belém], merged["geography"]["airbnb_freguesias"]
      end
    end
  end
end
