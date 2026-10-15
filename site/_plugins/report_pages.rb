# frozen_string_literal: true

require "fileutils"
require_relative "../../lib/alojamento_local"

class SnapshotReportGenerator < Jekyll::Generator
  safe true

  def generate(site)
    template = site.pages.find { |page| page.relative_path == "report.html" }
    raise "Missing shared report page" unless template
    site.pages.delete(template)
    report_only = ENV["REPORT_RUN"]
    if report_only
      site.pages.clear
      site.static_files.clear
      site.config["report_runs"] = [File.expand_path(report_only)]
    end

    loader = AlojamentoLocal::PublicSnapshot::Loader.new
    site.config.fetch("report_runs").each do |path|
      if report_only
        local = loader.metadata(path).fetch("mode") == "local"
        raise "Unsupported archive: verified reanalysis is required to build a report." unless local || loader.supported_metrics?(path)
        raise "Report destination must be separate from its input" if site.dest == path || site.dest.start_with?(path + "/") || path.start_with?(site.dest + "/")
      else
        next unless loader.supported_metrics?(path)
      end
      snapshot = loader.load(path, local: local == true)
      folder = report_only ? "" : "runs/#{snapshot.run_id}"
      name = local ? "report_local.html" : "report.html"
      page = Jekyll::PageWithoutAFile.new(site, site.source, folder, name)
      page.data = template.data.merge("layout" => nil, "report" => snapshot.to_h)
      page.content = template.content
      site.pages << page
    end
  end
end

# Jekyll has written the complete HTML, and Tailwind's normal hook has finished.
Jekyll::Hooks.register :site, :post_write, priority: :low do |site|
  report_only = ENV["REPORT_RUN"]
  reports = site.pages.select { |page| page.data.key?("report") }
  local_report = reports.any? { |page| page.data.fetch("report").fetch("metadata").fetch("mode") == "local" }
  site.config.fetch("report_runs").each do |source|
    next if local_report
    destination = report_only ? site.dest : File.join(site.dest, "runs", File.basename(source))
    FileUtils.mkdir_p(destination)
    files = if File.file?(File.join(source, "snapshot.json"))
      ["snapshot.json"]
    else
      %w[metadata.json summary.json listings.csv licence_groups.csv freguesias.csv registration_metrics.json]
        .select { |file| File.file?(File.join(source, file)) }
    end
    files.each { |file| FileUtils.cp(File.join(source, file), destination) }
  end
  reports.each do |page|
    html = page.destination(site.dest)
    AlojamentoLocal::ReportPdf.convert(html, File.join(File.dirname(html), "report.pdf"))
  end
  unless report_only
    %w[LICENSE NOTICE].each { |file| FileUtils.cp(File.join(AlojamentoLocal::SiteData::ROOT, file), site.dest) }
  end
end
