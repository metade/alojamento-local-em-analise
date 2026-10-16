require "csv"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../lib/alojamento_local"

# Only synthetic sources. No downloader, repository snapshots or private cache.
module PipelineFixture
  ROOT = File.expand_path("../fixtures/pipeline", __dir__)
  SOURCES = File.join(ROOT, "sources")
  EXPECTED = File.join(ROOT, "expected")
  RUN_ID = "2024-06-01__2024-07-01"

  def self.outputs(root)
    files = {}
    %w[public local].each do |mode|
      history = File.join(root, "#{mode}-history", "summary.csv")
      FileUtils.mkdir_p(File.dirname(history))
      FileUtils.cp(File.join(SOURCES, "summary_history.csv"), history)
      result = AlojamentoLocal::Analysis.run(
        airbnb_path: File.join(SOURCES, "listings-2024-06-01.csv"),
        official_path: File.join(SOURCES, "official-2024-07-01.csv"),
        output_root: File.join(root, mode), history_path: history, mode: mode
      )
      collect(files, result.fetch(:path), mode)
      collect(files, File.dirname(history), "#{mode}-history")
    end
    builder = AlojamentoLocal::SiteData.new(
      snapshots: File.join(root, "public"),
      distance_history: File.join(root, "public-history", "distance_ranges.csv"),
      outside_region_history: File.join(root, "public-history", "outside_regions.csv"),
      quotes: File.join(SOURCES, "quotes.json")
    )
    files["site.json"] = canonical("site.json", JSON.generate(builder.site_data(builder.public_runs)))
    files
  end

  def self.collect(files, directory, prefix)
    Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort.each do |path|
      relative = "#{prefix}/#{path.delete_prefix(directory + '/')}"
      files[relative] = canonical(relative, File.read(path))
    end
  end

  def self.canonical(path, text)
    if path.end_with?(".json")
      data = JSON.parse(text)
      case File.basename(path)
      when "snapshot.json"
        normalize_metadata(data.fetch("metadata"))
        normalize_summary(data.fetch("summary"))
      when "site.json"
        normalize_metadata(data.fetch("metadata"))
        normalize_summary(data.fetch("summary"))
      end
      JSON.pretty_generate(data) + "\n"
    elsif path.end_with?(".html")
      text.sub(/(· gerado em )\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/, '\1<generated_at>')
    elsif path.end_with?("-history/summary.csv")
      table = CSV.parse(text, headers: true)
      table.each { |row| row["generated_at"] = "<generated_at>" if row["run_id"] == RUN_ID }
      table.to_csv
    else
      text
    end
  end

  def self.normalize_metadata(data)
    data["git_commit"] = "<git_commit>" if data.key?("git_commit")
    data["git_worktree_dirty"] = "<git_worktree_dirty>" if data.key?("git_worktree_dirty")
  end

  def self.normalize_summary(data)
    data["generated_at"] = "<generated_at>" if data.key?("generated_at")
  end
end
