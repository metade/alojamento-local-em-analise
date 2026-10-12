#!/usr/bin/env ruby
# frozen_string_literal: true

# Jekyll is responsible for the editorial site. This boundary script selects
# public analysis runs, prepares Liquid data, and invokes the site generator.

require "fileutils"
require_relative "../lib/alojamento_local/site_data"

ROOT = AlojamentoLocal::SiteData::ROOT
SNAPSHOTS = AlojamentoLocal::SiteData::SNAPSHOTS
SOURCE = AlojamentoLocal::SiteData::SOURCE
SITE = AlojamentoLocal::SiteData::SITE
PUBLIC_FILES = AlojamentoLocal::SiteData::PUBLIC_FILES

builder = AlojamentoLocal::SiteData.new
runs = builder.public_runs
abort "Não existem snapshots públicos em #{SNAPSHOTS}." if runs.empty?

selected = builder.measured_run(runs)
data = builder.site_data(runs)
warn "Newest snapshot #{File.basename(runs.first)} lacks supported set metrics; site uses #{File.basename(selected)}" unless selected == runs.first

FileUtils.rm_rf(SITE)
FileUtils.mkdir_p(File.join(SOURCE, "_data"))
File.write(File.join(SOURCE, "_data", "site.json"), JSON.pretty_generate(data))

jekyll = ["bundle", "exec", "jekyll", "build", "--config", File.join(ROOT, "_config.yml")]
jekyll.concat(["--baseurl", ENV["JEKYLL_BASEURL"]]) if ENV["JEKYLL_BASEURL"]
system(*jekyll, chdir: ROOT, exception: true)

runs.each do |source|
  destination = File.join(SITE, "runs", File.basename(source))
  FileUtils.mkdir_p(destination)
  downloads = PUBLIC_FILES + %w[registration_metrics.json snapshot.json].select { |file| File.file?(File.join(source, file)) }
  downloads.each { |file| FileUtils.cp(File.join(source, file), File.join(destination, file)) }
end
FileUtils.cp(File.join(ROOT, "LICENSE"), File.join(SITE, "LICENSE"))
FileUtils.cp(File.join(ROOT, "NOTICE"), File.join(SITE, "NOTICE"))
system("bundle", "exec", "ruby", "scripts/check_site.rb", SITE, chdir: ROOT, exception: true)
system("bundle", "exec", "ruby", "scripts/audit_publication.rb", "--artifact", SITE, chdir: ROOT, exception: true)
puts "Site Jekyll criado em #{SITE} (#{data["districts"].length} freguesias)."
