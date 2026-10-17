require "fileutils"
require "json"
require "tmpdir"

module AlojamentoLocal
  module Analysis
    # Validate staged bytes before atomically replacing the sole output file.
    class ResultPublisher
      def initialize(destination:)
        @destination = destination
      end

      def publish(dataset:, sources:)
        FileUtils.mkdir_p(@destination)
        # The stable destination directory also serializes writers without a
        # separate lock file or auxiliary output directory.
        File.open(@destination, "r") do |lock|
          lock.flock(File::LOCK_EX)
          Dir.mktmpdir(".candidate-", @destination) do |stage|
            write_snapshot(File.join(stage, CandidateDataset::FILE), dataset.document)
            CandidateDataset.new(stage)
            sources.verify_unchanged!
            File.rename(File.join(stage, CandidateDataset::FILE), File.join(@destination, CandidateDataset::FILE))
          end
        end
      end

      private

      def write_snapshot(path, snapshot)
        File.open(path, "w") do |file|
          file.write(JSON.pretty_generate(snapshot) + "\n")
          file.flush
          file.fsync
        end
      end
    end
  end
end
