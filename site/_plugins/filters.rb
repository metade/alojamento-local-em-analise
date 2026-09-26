module SiteFilters
  def pt_number(value)
    value.to_i.to_s.reverse.gsub(/\d{3}(?=\d)/, "\\0 ").reverse
  end
end

Liquid::Template.register_filter(SiteFilters)
