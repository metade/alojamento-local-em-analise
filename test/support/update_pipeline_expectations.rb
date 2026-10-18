#!/usr/bin/env ruby
require_relative "pipeline_fixture"

abort "Usage: ruby test/support/update_pipeline_expectations.rb --write (review every diff before committing)" unless ARGV == ["--write"]
PipelineFixture.with_sources do |root, airbnb, official|
  result = PipelineFixture.run(root, airbnb, official)
  dataset = AlojamentoLocal::CandidateDataset.new(result.fetch(:path))
  dataset.write_files(File.join(PipelineFixture::EXPECTED, "public"))
end
puts "Synthetic expectations written. Review the complete diff and the independent accounting assertions."
