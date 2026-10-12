require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = false
end

task default: :test

def print_analysis_result(result)
  if result[:reused]
    puts "Run #{result[:run_id]} já existe; a análise pública será reutilizada sem reescrever o snapshot."
  else
    puts "Run #{result[:run_id]} criado em #{result[:path]}"
    puts JSON.pretty_generate(result[:summary])
  end
end

namespace :analysis do
  desc "Run the local analysis (FORCE=1 preserves an existing run as a sibling rerun)"
  task :local do
    require_relative "lib/alojamento_local"
    result = AlojamentoLocal::Analysis::Runner.run(mode: "local",
      force: ENV["FORCE"] == "1", reuse_existing: ENV["REUSE_EXISTING"] == "1",
      generate_pdf: ENV["GENERATE_PDF"] == "1")
    print_analysis_result(result)
  end

  desc "Run the public analysis (REUSE_EXISTING=1 reuses current outputs)"
  task :public do
    require_relative "lib/alojamento_local"
    result = AlojamentoLocal::Analysis::Runner.run(mode: "public",
      force: ENV["FORCE"] == "1", reuse_existing: ENV["REUSE_EXISTING"] == "1",
      generate_pdf: ENV["GENERATE_PDF"] == "1")
    print_analysis_result(result)
  end
end

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
