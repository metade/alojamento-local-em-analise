require "jekyll"
require_relative "../../lib/alojamento_local"

module JekyllBuild
  def self.build(destination:, run_dir: nil, baseurl: "", serving: false)
    previous = ENV["REPORT_RUN"]
    ENV["REPORT_RUN"] = run_dir
    config = Jekyll.configuration("config" => File.join(AlojamentoLocal::SiteData::ROOT, "_config.yml"),
      "source" => AlojamentoLocal::SiteData::SOURCE, "destination" => destination, "baseurl" => baseurl, "serving" => serving)
    site = Jekyll::Site.new(config)
    site.process
    site
  ensure
    ENV["REPORT_RUN"] = previous
  end
end
