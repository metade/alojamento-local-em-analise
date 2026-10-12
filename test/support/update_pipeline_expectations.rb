#!/usr/bin/env ruby
require_relative "pipeline_fixture"

abort "Usage: ruby test/support/update_pipeline_expectations.rb --write (review every diff before committing)" unless ARGV == ["--write"]
Dir.mktmpdir("pipeline-expectations-") do |root|
  PipelineFixture.outputs(root).each do |relative, text|
    path = File.join(PipelineFixture::EXPECTED, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end
end
puts "Synthetic expectations written. Review the complete diff and the independent accounting assertions."
