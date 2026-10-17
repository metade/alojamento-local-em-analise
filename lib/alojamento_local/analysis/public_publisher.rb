require "fileutils"
require "tmpdir"

module AlojamentoLocal
  module Analysis
    # Validate staged bytes before atomically replacing the sole output file.
    class PublicPublisher
      def initialize(destination:)
        @destination = destination
      end

      def publish(result:, sources:)
        FileUtils.mkdir_p(@destination)
        # The stable destination directory also serializes writers without a
        # separate lock file or auxiliary output directory.
        File.open(@destination, "r") do |lock|
          lock.flock(File::LOCK_EX)
          Dir.mktmpdir(".candidate-", @destination) do |stage|
            OutputWriter.new(result: result).generate_data(stage)
            CandidateDataset.new(stage)
            sources.verify_unchanged!
            File.rename(File.join(stage, CandidateDataset::FILE), File.join(@destination, CandidateDataset::FILE))
          end
        end
      end
    end
  end
end
