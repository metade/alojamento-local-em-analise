# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module AlojamentoLocal
  module Analysis
    # Installs a validated snapshot and its histories as one rollback unit.
    class PublicPublisher
      def initialize(destination:, history_path:)
        @destination = destination
        @history_path = history_path
      end

      def publish(summary:, listings:)
        root = File.dirname(@destination)
        FileUtils.mkdir_p(root)
        staging = Dir.mktmpdir(".analysis-", root)
        begin
          run_dir = File.join(staging, "snapshot")
          yield run_dir
          self.class.validate_public_outputs!(run_dir)
          histories = stage_histories(staging, summary, listings)
          self.class.publish_public_run!(run_dir, @destination, histories, staging)
        ensure
          FileUtils.rm_rf(staging)
        end
      end

      def self.verify_public_sources!(path, hashes)
        loader = PublicSnapshot::Loader.new
        metadata = loader.metadata(path)
        expected = {"airbnb" => hashes[0], "official" => hashes[1]}
        unless expected.all? { |key, hash| metadata.dig("source_files", key, "sha256") == hash }
          raise "Source hashes differ for existing dated snapshot: #{path}"
        end
      end

      def self.validate_public_outputs!(run_dir)
        loader = PublicSnapshot::Loader.new
        loader.load(run_dir, expected_run_id: loader.metadata(run_dir).fetch("run_id"))
      end

      def self.publish_public_run!(staged_run, destination, histories, staging)
        installed = []
        {staged_run => destination, **histories}.each_with_index do |(source, target), index|
          FileUtils.mkdir_p(File.dirname(target))
          backup = File.join(staging, "previous-#{index}")
          existed = File.exist?(target)
          FileUtils.mv(target, backup) if existed
          installed << [target, existed ? backup : nil]
          FileUtils.mv(source, target)
        end
      # Roll back even on interruption or exit, then propagate the exception.
      rescue Exception # standard:disable Lint/RescueException
        installed.reverse_each do |target, backup|
          FileUtils.rm_rf(target)
          FileUtils.mv(backup, target) if backup && File.exist?(backup)
        end
        raise
      end

      private

      def stage_histories(staging, summary, listings)
        histories = %w[summary.csv distance_ranges.csv outside_regions.csv].to_h do |filename|
          target = (filename == "summary.csv") ? @history_path : File.join(File.dirname(@history_path), filename)
          staged_path = File.join(staging, filename)
          FileUtils.cp(target, staged_path) if File.file?(target)
          [staged_path, target]
        end
        run_id = summary.fetch(:run_id)
        History.append_history(File.join(staging, "summary.csv"), summary, replace: true)
        History.append_distance_history(File.join(staging, "distance_ranges.csv"), run_id, listings, replace: true)
        History.append_outside_region_history(File.join(staging, "outside_regions.csv"), run_id, listings, replace: true)
        histories
      end
    end
  end
end
