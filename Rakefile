require "rake/testtask"

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

  desc "Stage the latest local source pair for an Actions artifact"
  task :archive do
    require_relative "lib/alojamento_local"
    puts AlojamentoLocal::Analysis::Data.archive!
  end
end

namespace :analysis do
  desc "Analyse local sources with detailed outputs (no downloads)"
  task :local do
    require_relative "lib/alojamento_local"
    result = AlojamentoLocal::Analysis.run(mode: "local")
    print_analysis_result(result)
  end

  desc "Analyse local sources with public outputs (no downloads)"
  task :public do
    require_relative "lib/alojamento_local"
    result = AlojamentoLocal::Analysis.run(mode: "public")
    print_analysis_result(result)
  end
end

desc "Analyse local sources into public outputs, then build the site"
task rebuild: ["analysis:public", "site:build"]

desc "Update sources, analyse into public outputs, then build the site"
task refresh: ["sources:update", :rebuild]

namespace :site do
  desc "Build and validate the public site from existing snapshots"
  task :build do
    require_relative "lib/alojamento_local"
    result = AlojamentoLocal::SiteBuilder.new.build(baseurl: ENV["JEKYLL_BASEURL"])
    warn result[:warning] if result[:warning]
    puts "Site Jekyll criado em #{result[:path]} (#{result[:districts]} freguesias)."
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
  desc "Build standalone HTML and PDF from a public or local run (DESTINATION overrides output)"
  task :build, [:run_dir] do |_task, args|
    require_relative "lib/alojamento_local"
    raise "Usage: rake 'report:build[run_dir]'" unless args[:run_dir]
    puts AlojamentoLocal::SiteBuilder.new.build(run_dir: args[:run_dir], destination: ENV["DESTINATION"]).fetch(:path)
  end
end
