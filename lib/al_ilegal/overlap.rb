module AlIlegal
  # Used by scripts/build_site.rb to draw the area-proportional Venn diagrams
  # on the homepage and district pages. Converts saved set counts into SVG
  # circle radii and positions; the statistical counts are calculated elsewhere.
  module Overlap
    def self.area(r, s, d)
      return 0.0 if r.zero? || s.zero? || d >= r + s
      return Math::PI * [r, s].min**2 if d <= (r - s).abs
      r*r*Math.acos([[((d*d+r*r-s*s)/(2*d*r)), -1].max, 1].min) +
        s*s*Math.acos([[((d*d+s*s-r*r)/(2*d*s)), -1].max, 1].min) -
        0.5*Math.sqrt([(-d+r+s)*(d+r-s)*(d-r+s)*(d+r+s), 0].max)
    end

    def self.geometry(a, b, intersection)
      raise ArgumentError, "Invalid sets" unless [a,b,intersection].all? { |n| n.is_a?(Numeric) && n >= 0 } && intersection <= [a,b].min
      return {"r" => 0, "s" => 0, "x" => 240, "y" => 400, "distance" => 160} if [a,b].max.zero?
      scale = 170.0 / Math.sqrt([a,b].max)
      r, s = Math.sqrt(a)*scale, Math.sqrt(b)*scale
      low, high = (r-s).abs, r+s
      if intersection.zero?
        d = high + 16
      elsif intersection == [a,b].min
        d = low
      else
        target = intersection * scale**2 * Math::PI
        80.times do
          midpoint = (low+high)/2
          area(r,s,midpoint) > target ? low = midpoint : high = midpoint
        end
        d = (low+high)/2
      end
      width = r+d+s
      fit = [600.0/[width,1].max,1].min
      r *= fit; s *= fit; d *= fit
      left = (640-(r+d+s))/2
      {"r" => r.round(6), "s" => s.round(6), "x" => (left+r).round(6), "y" => (left+r+d).round(6), "distance" => d.round(6)}
    end
  end
end
