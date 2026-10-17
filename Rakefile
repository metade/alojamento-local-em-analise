require "rake/testtask"
require "json"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = false
end

task default: :test

def print_analysis_result(result)
  puts "Run #{result[:run_id]} criado em #{result[:path]}"
  puts JSON.pretty_generate(result[:summary])
end

namespace :sources do
  desc "Update sources when needed (FORCE=1 downloads both sources again)"
  task :update do
    require_relative "lib/alojamento_local"
    puts AlojamentoLocal::Analysis::Data.update!(force: ENV["FORCE"] == "1")
  end

  desc "Register cached source provenance offline (unknown fetch dates stay null)"
  task :register do
    require_relative "lib/alojamento_local"
    puts JSON.pretty_generate(AlojamentoLocal::Analysis::Data.register!)
  end

  desc "Stage the latest local source pair for an Actions artifact"
  task :archive do
    require_relative "lib/alojamento_local"
    puts AlojamentoLocal::Analysis::Data.archive!
  end
end

desc "Analyse the latest dated local source pair without downloads"
task :analysis do
  require_relative "lib/alojamento_local"
  raise ArgumentError, "analysis no longer accepts a run ID; pass paired source paths to Analysis.run in Ruby" unless Rake.application.top_level_tasks.none? { |name| name.start_with?("analysis[") }
  print_analysis_result(AlojamentoLocal::Analysis.run)
end

desc "Analyse local sources into public outputs, then build the site"
task rebuild: [:analysis, "site:build"]

desc "Update sources, analyse into public outputs, then build the site"
task refresh: ["sources:update", :rebuild]

def selected_download
  path = ENV["SNAPSHOT"] || AlojamentoLocal::CandidateDataset.default_path
  AlojamentoLocal::CandidateDataset.new(path).download_path.delete_prefix("/")
end

namespace :site do
  desc "Build and validate the site from cleaned RNAL and candidate data"
  task :build do
    require_relative "lib/alojamento_local"
    destination = File.expand_path(ENV["DESTINATION"] || "_site", __dir__)
    command = ["bundle", "exec", "jekyll", "build", "--destination", destination]
    command.concat(["--baseurl", ENV["JEKYLL_BASEURL"]]) if ENV["JEKYLL_BASEURL"]
    sh(*command)
    result = AlojamentoLocal::SiteChecker.check(File.expand_path(ENV["DESTINATION"] || "_site", __dir__), required: AlojamentoLocal::SiteChecker::REQUIRED_FILES + ["report.html", "report.pdf", selected_download])
    sh "bundle", "exec", "ruby", "scripts/audit_publication.rb", "--artifact", destination
    puts "Site Jekyll criado em #{destination} (#{result[:districts]} freguesias)."
  end

  desc "Check the generated site's structure"
  task :check do
    require_relative "lib/alojamento_local"
    result = AlojamentoLocal::SiteChecker.check(File.expand_path(ENV["DESTINATION"] || "_site", __dir__), required: AlojamentoLocal::SiteChecker::REQUIRED_FILES + ["report.html", "report.pdf", selected_download])
    puts "Site verificado: #{result[:html_pages]} páginas HTML, #{result[:districts]} freguesias."
  end

  desc "Build the site and capture screenshots (optional page path)"
  task :screenshots, [:page] => :build do |_task, args|
    sh "node", "scripts/capture_homepage.mjs", args[:page] || "index.html", ENV["DESTINATION"] || "_site"
  end
end

namespace :report do
  desc "Build standalone HTML/PDF from a candidate dataset directory (DESTINATION overrides output)"
  task :build, [:run_dir] do |_task, args|
    require_relative "lib/alojamento_local"
    raise "Usage: rake 'report:build[run_dir]'" unless args[:run_dir]
    input = File.expand_path(args[:run_dir])
    AlojamentoLocal::CandidateDataset.new(input)
    destination = File.expand_path(ENV["DESTINATION"] || File.join("tmp", "reports", File.basename(input)))
    sh({"REPORT_RUN" => input}, "bundle", "exec", "jekyll", "build", "--destination", destination)
    html = "report.html"
    AlojamentoLocal::SiteChecker.check(destination, required: [html, "report.pdf"])
    puts destination
  end
end
