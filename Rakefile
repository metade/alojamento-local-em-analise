require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = false
end

task default: :test

def print_analysis_result(result)
  puts "Run #{result[:run_id]} criado em #{result[:path]}"
  puts "Diagnósticos privados em #{result[:private_path]}"
  puts JSON.pretty_generate(result[:summary])
end

namespace :sources do
  desc "Update sources when needed (FORCE=1 downloads both sources again)"
  task :update do
    require_relative "lib/alojamento_local"
    puts AlojamentoLocal::Analysis::Data.update!(force: ENV["FORCE"] == "1")
  end

  desc "Stage the latest local source pair for an Actions artifact"
  task :archive do
    require_relative "lib/alojamento_local"
    puts AlojamentoLocal::Analysis::Data.archive!
  end
end

desc "Analyse latest local sources or verified sources of an existing run (no downloads)"
task :analysis, [:run_id] do |_task, args|
  require_relative "lib/alojamento_local"

  paths = {}
  if (run_id = args[:run_id])
    snapshot = AlojamentoLocal::PublicSnapshot.load_run(run_id)
    airbnb, official = AlojamentoLocal::Analysis::Data.local_paths_for_snapshot!(snapshot)
    paths = {airbnb_path: airbnb, official_path: official}
  end
  print_analysis_result(AlojamentoLocal::Analysis.run(**paths))
end

desc "Analyse local sources into public outputs, then build the site"
task rebuild: [:analysis, "site:build"]

desc "Update sources, analyse into public outputs, then build the site"
task refresh: ["sources:update", :rebuild]

namespace :site do
  desc "Build and validate the public site from existing snapshots"
  task :build do
    require_relative "lib/alojamento_local"
    command = ["bundle", "exec", "jekyll", "build"]
    command.concat(["--baseurl", ENV["JEKYLL_BASEURL"]]) if ENV["JEKYLL_BASEURL"]
    sh(*command)
    result = AlojamentoLocal::SiteChecker.check(File.join(__dir__, "_site"))
    sh "bundle", "exec", "ruby", "scripts/audit_publication.rb", "--artifact", "_site"
    puts "Site Jekyll criado em _site (#{result[:districts]} freguesias)."
  end

  desc "Check the generated site's structure"
  task :check do
    require_relative "lib/alojamento_local"
    result = AlojamentoLocal::SiteChecker.check(File.join(__dir__, "_site"))
    puts "Site verificado: #{result[:html_pages]} páginas HTML, #{result[:districts]} freguesias."
  end

  desc "Build the site and capture screenshots (optional page path)"
  task :screenshots, [:page] => :build do |_task, args|
    sh "node", "scripts/capture_homepage.mjs", args[:page] || "index.html"
  end
end

namespace :report do
  desc "Build standalone HTML and PDF from an aggregate snapshot (DESTINATION overrides output)"
  task :build, [:run_dir] do |_task, args|
    require_relative "lib/alojamento_local"
    raise "Usage: rake 'report:build[run_dir]'" unless args[:run_dir]
    input = File.expand_path(args[:run_dir])
    AlojamentoLocal::PublicSnapshot.load(input)
    destination = File.expand_path(ENV["DESTINATION"] || File.join("tmp", "reports", File.basename(input)))
    sh({"REPORT_RUN" => input}, "bundle", "exec", "jekyll", "build", "--destination", destination)
    html = "report.html"
    AlojamentoLocal::SiteChecker.check(destination, required: [html, "report.pdf"])
    puts destination
  end
end
