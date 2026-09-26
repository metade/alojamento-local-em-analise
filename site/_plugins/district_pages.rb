class DistrictPage < Jekyll::PageWithoutAFile
  def initialize(site, district)
    @site = site
    @base = site.source
    @dir = File.join("freguesias", district["slug"])
    @name = "index.html"
    process(@name)
    self.data = {
      "layout" => "district",
      "title" => "O alojamento local em #{district["display_name"]}",
      "district" => district
    }
    self.content = ""
  end
end

Jekyll::Hooks.register :site, :post_read do |site|
  site.data.fetch("site", {}).fetch("districts", []).each do |district|
    site.pages << DistrictPage.new(site, district)
  end
end
