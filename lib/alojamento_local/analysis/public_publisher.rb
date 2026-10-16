# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module AlojamentoLocal
  module Analysis
    # Installs a validated snapshot, private diagnostics and histories as one rollback unit.
    class PublicPublisher
      def initialize(destination:, history_path:, private_path:)
        @destination = destination
        @history_path = history_path
        @private_path = private_path
      end

      def publish(summary:, listings:)
        root = File.dirname(@destination)
        FileUtils.mkdir_p(root)
        staging = Dir.mktmpdir(".analysis-", root)
        begin
          run_dir = File.join(staging, "snapshot")
          diagnostics = File.join(staging, "private")
          yield run_dir, diagnostics
          preserve_archived_reports(run_dir)
          validate_public_outputs!(run_dir)
          histories = stage_histories(staging, summary, listings)
          install(run_dir, {diagnostics => @private_path, **histories}, staging)
        ensure
          FileUtils.rm_rf(staging)
        end
      end

      def self.verify_public_sources!(path, hashes)
        metadata = PublicSnapshot.load(path).fetch("metadata")
        expected = {"airbnb" => hashes[0], "official" => hashes[1]}
        unless expected.all? { |key, hash| metadata.dig("source_files", key, "sha256") == hash }
          raise "Source hashes differ for existing dated snapshot: #{path}"
        end
      end

      private

      def preserve_archived_reports(run_dir)
        %w[report.html report.pdf].each do |file|
          source = File.join(@destination, file)
          FileUtils.cp(source, File.join(run_dir, file)) if File.file?(source)
        end
      end

      def validate_public_outputs!(run_dir)
        PublicSnapshot.load(run_dir, expected_run_id: File.basename(@destination))
      end

      def install(staged_run, histories, staging)
        installed = []
        {staged_run => @destination, **histories}.each_with_index do |(source, target), index|
          FileUtils.mkdir_p(File.dirname(target))
          backup = File.join(staging, "previous-#{index}")
          existed = File.exist?(target)
          FileUtils.mv(target, backup) if existed
          installed << [target, existed ? backup : nil]
          FileUtils.mv(source, target)
        end
      # Roll back even on interruption or exit, then propagate the exception.
      rescue Exception # standard:disable Lint/RescueException
        rollback(installed)
        raise
      end

      def rollback(installed)
        installed.reverse_each do |target, backup|
          FileUtils.rm_rf(target)
          FileUtils.mv(backup, target) if backup && File.exist?(backup)
        end
      end

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
