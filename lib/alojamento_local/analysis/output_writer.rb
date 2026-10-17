require "json"
require "fileutils"

module AlojamentoLocal
  module Analysis
    class OutputWriter
      def initialize(result:)
        @result = result
      end

      def generate_data(path)
        write(File.join(path, CandidateDataset::FILE), @result.snapshot)
      end

      private

      def write(path, data)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "w") do |file|
          file.write(JSON.pretty_generate(data) + "\n")
          file.flush
          file.fsync
        end
      end
    end
  end
end
