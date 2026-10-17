require "json"

module AlojamentoLocal
  module Analysis
    # Full-resolution CML polygons; bboxes only accelerate the exact ray test.
    class Boundaries
      PATH = File.expand_path("../../../data/freguesia_boundaries.json", __dir__)

      def initialize(path = PATH)
        @polygons = JSON.parse(File.read(path)).fetch("features").flat_map do |feature|
          geometry = feature.fetch("geometry")
          polygons = (geometry["type"] == "MultiPolygon") ? geometry["coordinates"] : [geometry.fetch("coordinates")]
          polygons.map do |rings|
            points = rings.first
            [feature.fetch("freguesia"), rings, [points.map(&:first).minmax, points.map(&:last).minmax]]
          end
        end
      end

      def parish(coordinates)
        return nil unless coordinates
        y, x = coordinates
        matches = @polygons.filter_map do |name, rings, (xs, ys)|
          next unless x.between?(*xs) && y.between?(*ys)
          name if inside?(rings.first, x, y) && rings.drop(1).none? { |ring| inside?(ring, x, y) }
        end.uniq
        matches.first if matches.size == 1
      end

      private

      def inside?(ring, x, y)
        inside = false
        ring.each_cons(2) do |(ax, ay), (bx, by)|
          # Exact boundary points are included, but multiple matches stay unknown.
          cross = (x - ax) * (by - ay) - (y - ay) * (bx - ax)
          return true if cross.abs < 1e-14 && x.between?(*[ax, bx].minmax) && y.between?(*[ay, by].minmax)
          inside = !inside if (ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax
        end
        inside
      end
    end
  end
end
