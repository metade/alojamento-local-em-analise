require "fileutils"
require "tmpdir"

module AlojamentoLocal
  module Analysis
    # Stage and validate a complete pair before installing under the parent lock.
    class ResultPublisher
      def initialize(destination:)
        @destination = File.expand_path(destination)
      end

      def publish(dataset:, sources:)
        parent = File.dirname(@destination)
        FileUtils.mkdir_p(parent)
        stage = Dir.mktmpdir(".candidate-", parent)
        backup = nil
        committed = false
        begin
          dataset.write_files(stage)
          CandidateDataset.new(stage)
          CandidateDataset.with_lock(@destination, File::LOCK_EX) do
            sources.verify_unchanged!
            installed = false
            begin
              Thread.handle_interrupt(Interrupt => :never) do
                if File.exist?(@destination)
                  backup = Dir.mktmpdir(".previous-", parent)
                  Dir.rmdir(backup)
                  File.rename(@destination, backup)
                end
                installed = true
                File.rename(stage, @destination)
              end
              committed = true
            rescue Exception
              FileUtils.rm_rf(@destination) if installed
              File.rename(backup, @destination) if backup && File.exist?(backup)
              raise
            end
          end
        ensure
          FileUtils.rm_rf(stage) if stage && File.exist?(stage)
          FileUtils.rm_rf(backup) if committed && backup && File.exist?(backup)
        end
      end
    end
  end
end
