# frozen_string_literal: true

Jekyll::Hooks.register :site, :post_read do |site|
  next if ENV["REPORT_RUN"]
  site.data.fetch("site", {}).fetch("districts", []).each do |district|
    page = Jekyll::PageWithoutAFile.new(site, site.source, "freguesias/#{district.fetch("slug")}", "index.html")
    page.data = {
      "layout" => "district",
      "title" => "O alojamento local em #{district.fetch("display_name")}",
      "district" => district
    }
    site.pages << page
  end
end
