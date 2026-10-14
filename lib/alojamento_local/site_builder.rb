# frozen_string_literal: true

require "fileutils"
require "json"
require "jekyll"

module AlojamentoLocal
  class SiteBuilder
    def build(baseurl: nil, run_dir: nil, destination: nil)
      if run_dir
        input = File.expand_path(run_dir)
        if File.file?(File.join(input, "metadata_local.json")) && !File.file?(File.join(input, PublicSnapshot::FILE))
          raise "Missing snapshot.json; create a new local analysis rerun to regenerate this report."
        end
        loader = PublicSnapshot::Loader.new
        local = loader.metadata(input).fetch("mode") == "local"
        raise "Unsupported archive: verified reanalysis is required to build a report." unless local || loader.supported_metrics?(input)
        snapshot = loader.load(input, local: local)
        runs = [input]
        destination ||= File.join(SiteData::ROOT, "tmp", "reports", local ? "local" : "public", snapshot.run_id)
        destination = File.expand_path(destination)
        raise "Report destination must be separate from its input" if destination == input || destination.start_with?(input + "/") || input.start_with?(destination + "/")
      else
        builder = SiteData.new
        runs = builder.public_runs
        raise "Não existem snapshots públicos em #{SiteData::SNAPSHOTS}." if runs.empty?
        selected = builder.measured_run(runs)
        data = builder.site_data(runs)
        File.write(File.join(SiteData::SOURCE, "_data", "site.json"), JSON.pretty_generate(data))
        destination ||= SiteData::SITE
      end

      config = Jekyll.configuration("config" => File.join(SiteData::ROOT, "_config.yml"),
        "source" => SiteData::SOURCE, "destination" => File.expand_path(destination),
        "report_runs" => runs, "report_only" => !run_dir.nil?, "local_report" => local == true)
      config["baseurl"] = baseurl if baseurl
      site = Jekyll::Site.new(config)
      site.process
      runs.each { |source| copy_run(source, site.dest, report_only: !run_dir.nil?) } unless local
      required = run_dir ? [] : SiteChecker::REQUIRED_FILES.dup
      site.pages.select { |page| page.data.key?("report") }.each do |page|
        html = page.destination(site.dest)
        pdf = File.join(File.dirname(html), "report.pdf")
        ReportPdf.convert(html, pdf)
        route = page.url.delete_prefix("/")
        required.concat([route, File.join(File.dirname(route), "report.pdf")])
      end
      unless run_dir
        %w[LICENSE NOTICE].each { |file| FileUtils.cp(File.join(SiteData::ROOT, file), site.dest) }
      end
      SiteChecker.check(site.dest, required: required)
      unless run_dir
        system("bundle", "exec", "ruby", "scripts/audit_publication.rb", "--artifact", site.dest,
          chdir: SiteData::ROOT, exception: true)
      end
      {path: site.dest, districts: data ? data.fetch("districts").length : 0,
       warning: (!run_dir && selected != runs.first) ? "Newest snapshot #{File.basename(runs.first)} lacks supported set metrics; site uses #{File.basename(selected)}" : nil}
    end

    private

    def copy_run(source, destination, report_only: false)
      destination = File.join(destination, "runs", File.basename(source)) unless report_only
      FileUtils.mkdir_p(destination)
      downloads = if File.file?(File.join(source, PublicSnapshot::FILE))
        [PublicSnapshot::FILE]
      else
        %w[metadata.json summary.json listings.csv licence_groups.csv freguesias.csv registration_metrics.json]
          .select { |file| File.file?(File.join(source, file)) }
      end
      downloads.each { |file| FileUtils.cp(File.join(source, file), File.join(destination, file)) }
    end
  end
end
