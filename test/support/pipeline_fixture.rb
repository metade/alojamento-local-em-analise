require "csv"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../lib/alojamento_local"

module PipelineFixture
  ROOT = File.expand_path("../fixtures/pipeline", __dir__)
  SOURCES = File.join(ROOT, "sources")
  EXPECTED = File.join(ROOT, "expected")
  RUN_ID = "2024-06-01__2024-07-01"

  def self.with_sources
    Dir.mktmpdir("candidate-pipeline-") do |root|
      source = File.join(root, "sources")
      FileUtils.cp_r(SOURCES, source)
      yield root, File.join(source, "listings-2024-06-01.csv"), File.join(source, "official-2024-07-01.csv")
    end
  end

  def self.pair(airbnb, official)
    AlojamentoLocal::Analysis::DataSource.new(airbnb_path: airbnb, official_path: official)
  end

  def self.run(root, airbnb, official)
    AlojamentoLocal::Analysis.run(airbnb_path: airbnb, official_path: official,
      output_root: File.join(root, "public"))
  end
end
