# frozen_string_literal: true

require "csv"
require "fileutils"
require_relative "../../lib/alojamento_local"

class SnapshotReportGenerator < Jekyll::Generator
  safe true

  DIAGNOSTICS = {"licence_groups_detailed.csv" => "Grupos de licenças", "listings_detailed.csv" => "Anúncios"}.freeze
  UNFLAGGED_GROUP_CLASSIFICATIONS = [
    "licença única em Lisboa",
    "provável estabelecimento com anúncios múltiplos",
    "licença repetida na mesma localização"
  ].freeze

  def generate(site)
    template = site.pages.find { |page| page.relative_path == "report.html" }
    raise "Missing shared report page" unless template
    site.pages.delete(template)
    site.config["private_report_runs"] = []
    report_only = ENV["REPORT_RUN"]
    site.config["skip_report_pdfs"] = !!(site.config["serving"] && !report_only && ENV["SKIP_PDF"] == "1")
    if report_only
      site.pages.clear
      site.static_files.clear
      site.config["report_runs"] = [File.expand_path(report_only)]
    end

    site.config.fetch("report_runs").each do |path|
      if report_only
        raise "Report destination must be separate from its input" if site.dest == path || site.dest.start_with?(path + "/") || path.start_with?(site.dest + "/")
      end
      snapshot = AlojamentoLocal::PublicSnapshot.load(path)
      run_id = snapshot.fetch("metadata").fetch("run_id")
      add_report(site, template, snapshot, path, report_only ? "" : "runs/#{run_id}")
      next unless site.config["serving"] && !report_only

      private_dir = File.join(File.dirname(File.dirname(path)), "private", run_id)
      next unless DIAGNOSTICS.keys.all? { |file| File.file?(File.join(private_dir, file)) }
      groups = CSV.read(File.join(private_dir, "licence_groups_detailed.csv"), headers: true)
      rows = groups.map(&:to_h).reject { |row| UNFLAGGED_GROUP_CLASSIFICATIONS.include?(row["classification"]) }
      page = add_report(site, template, snapshot, path, "private-reports/#{run_id}")
      page.data["private_tables"] = [{"title" => DIAGNOSTICS.fetch("licence_groups_detailed.csv"),
        "filename" => "licence_groups_detailed.csv", "headers" => groups.headers,
        "rows" => rows, "total_rows" => groups.length}]
      page.data["private_listing_count"] = CSV.foreach(File.join(private_dir, "listings_detailed.csv"), headers: true).count
      page.data["diagnostics_dir"] = private_dir
      site.config["private_report_runs"] << run_id
    end
  end

  private

  def add_report(site, template, snapshot, source, folder)
    page = Jekyll::PageWithoutAFile.new(site, site.source, folder, "report.html")
    page.data = template.data.merge("layout" => nil, "report" => snapshot, "snapshot_source" => source)
    page.content = template.content
    site.pages << page
    page
  end
end

# Jekyll has written the complete HTML, and Tailwind's normal hook has finished.
Jekyll::Hooks.register :site, :post_write, priority: :low do |site|
  reports = site.pages.select { |page| page.data.key?("report") }
  reports.each do |page|
    html = page.destination(site.dest)
    destination = File.dirname(html)
    FileUtils.cp(File.join(page.data.fetch("snapshot_source"), "snapshot.json"), destination)
    if page.data["private_tables"]
      SnapshotReportGenerator::DIAGNOSTICS.each_key do |file|
        FileUtils.cp(File.join(page.data.fetch("diagnostics_dir"), file), destination)
      end
    end
    pdf = File.join(destination, "report.pdf")
    if site.config["skip_report_pdfs"]
      FileUtils.rm_f(pdf)
      Jekyll.logger.info "Report PDF:", "skipped (SKIP_PDF=1): #{html}"
    else
      Jekyll.logger.info "Report PDF:", html
      AlojamentoLocal::ReportPdf.convert(html, pdf)
    end
  end
  unless ENV["REPORT_RUN"]
    %w[LICENSE NOTICE].each { |file| FileUtils.cp(File.join(AlojamentoLocal::SiteData::ROOT, file), site.dest) }
  end
end
