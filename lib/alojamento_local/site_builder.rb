# frozen_string_literal: true

require "fileutils"
require_relative "site_data"
require_relative "site_checker"

module AlojamentoLocal
  class SiteBuilder
    def build(baseurl: nil)
      builder = SiteData.new
      runs = builder.public_runs
      raise "Não existem snapshots públicos em #{SiteData::SNAPSHOTS}." if runs.empty?

      selected = builder.measured_run(runs)
      data = builder.site_data(runs)

      FileUtils.rm_rf(SiteData::SITE)
      FileUtils.mkdir_p(File.join(SiteData::SOURCE, "_data"))
      File.write(File.join(SiteData::SOURCE, "_data", "site.json"), JSON.pretty_generate(data))

      jekyll = ["bundle", "exec", "jekyll", "build", "--config", File.join(SiteData::ROOT, "_config.yml")]
      jekyll.concat(["--baseurl", baseurl]) if baseurl
      system(*jekyll, chdir: SiteData::ROOT, exception: true)

      runs.each { |source| copy_run(source) }
      %w[LICENSE NOTICE].each do |file|
        FileUtils.cp(File.join(SiteData::ROOT, file), File.join(SiteData::SITE, file))
      end
      SiteChecker.check(SiteData::SITE)
      system("bundle", "exec", "ruby", "scripts/audit_publication.rb", "--artifact", SiteData::SITE,
        chdir: SiteData::ROOT, exception: true)

      {path: SiteData::SITE, districts: data.fetch("districts").length,
       warning: (selected == runs.first) ? nil : "Newest snapshot #{File.basename(runs.first)} lacks supported set metrics; site uses #{File.basename(selected)}"}
    end

    private

    def copy_run(source)
      destination = File.join(SiteData::SITE, "runs", File.basename(source))
      FileUtils.mkdir_p(destination)
      downloads = if File.file?(File.join(source, "snapshot.json"))
        SiteData::PUBLIC_FILES.dup
      else
        # Archived split-file runs retain their original download paths.
        %w[metadata.json summary.json listings.csv licence_groups.csv freguesias.csv report.html registration_metrics.json]
          .select { |file| File.file?(File.join(source, file)) }
      end
      downloads << "report.pdf" if File.file?(File.join(source, "report.pdf"))
      downloads.each { |file| FileUtils.cp(File.join(source, file), File.join(destination, file)) }
    end
  end
end
