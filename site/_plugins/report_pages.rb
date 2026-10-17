# frozen_string_literal: true

require "fileutils"
require_relative "../../lib/alojamento_local"

class CandidateReportGenerator < Jekyll::Generator
  safe true

  def generate(site)
    dataset = site.config.fetch("candidate_dataset")
    if ENV["REPORT_RUN"]
      input = dataset.path
      raise "Report destination must be separate from its input" if site.dest == input || site.dest.start_with?(input + "/") || input.start_with?(site.dest + "/")
      template = site.pages.find { |page| page.relative_path == "report.html" }
      site.pages.replace([template])
      site.static_files.clear
    end
    site.config["skip_report_pdfs"] = !!(site.config["serving"] && !ENV["REPORT_RUN"] && ENV["SKIP_PDF"] == "1")
  end
end

Jekyll::Hooks.register :site, :post_write, priority: :low do |site|
  dataset = site.config.fetch("candidate_dataset")
  destination = File.join(site.dest, "snapshots", File.basename(dataset.path))
  FileUtils.mkdir_p(destination)
  file = AlojamentoLocal::CandidateDataset::FILE
  FileUtils.cp(File.join(dataset.path, file), destination)
  pdf = File.join(site.dest, "report.pdf")
  if site.config["skip_report_pdfs"]
    FileUtils.rm_f(pdf)
  else
    AlojamentoLocal::ReportPdf.convert(File.join(site.dest, "report.html"), pdf)
  end
  %w[LICENSE NOTICE].each { |file| FileUtils.cp(File.join(AlojamentoLocal::SiteData::ROOT, file), site.dest) }
end
