# frozen_string_literal: true

require_relative "../../lib/alojamento_local"

class SnapshotReportGenerator < Jekyll::Generator
  safe true

  def generate(site)
    template = site.pages.find { |page| page.relative_path == "report.html" }
    raise "Missing shared report page" unless template
    site.pages.delete(template)
    if site.config["report_only"]
      site.pages.clear
      site.static_files.clear
    end

    loader = AlojamentoLocal::PublicSnapshot::Loader.new
    runs = site.config.fetch("report_runs") { Dir.glob(File.expand_path("../../data/snapshots/*", __dir__)).select { |path| File.directory?(path) } }
    runs.each do |path|
      local = site.config["local_report"] == true
      next unless local || loader.supported_metrics?(path)
      snapshot = loader.load(path, local: local)
      folder = site.config["report_only"] ? "" : "runs/#{snapshot.run_id}"
      name = local ? "report_local.html" : "report.html"
      page = Jekyll::PageWithoutAFile.new(site, site.source, folder, name)
      page.data = template.data.merge("layout" => nil, "report" => snapshot.to_h)
      page.content = template.content
      site.pages << page
    end
  end
end
