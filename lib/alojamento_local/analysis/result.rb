# frozen_string_literal: true

require "open3"
require "json"

module AlojamentoLocal
  module Analysis
    # Calculates the aggregates from classified listings and the complete
    # prepared register. Source selection, history and publication live outside.
    class Result
      attr_reader :listings, :licence_groups, :parish_totals, :announcements_by_parish_and_classification,
        :licence_group_aggregates, :metadata, :summary, :registration_metrics

      def initialize(sources:, run_id:, mode:)
        @sources = sources
        @run_id = run_id
        @mode = mode
        @listings, = Classifier.new(sources).classify
        @metadata = build_metadata
        @licence_groups = Aggregates.licence_groups(listings)
        @summary = Aggregates.summary(listings, licence_groups, metadata.fetch(:source_dates),
          metadata.fetch(:run_id), metadata.fetch(:mode), official: sources.official)
        @registration_metrics = RegistrationMetrics.calculate(listings, sources.official).merge(
          run_id: metadata.fetch(:run_id), source_files: metadata.fetch(:source_files),
          methodology_version: metadata.fetch(:methodology_version), source_dates: metadata.fetch(:source_dates)
        )
        @parish_totals = Aggregates.freguesia_rows(listings)
        @announcements_by_parish_and_classification = Aggregates.public_listing_rows(listings)
        @licence_group_aggregates = Aggregates.public_group_rows(licence_groups)
      end

      def snapshot
        inputs = JSON.parse(JSON.generate({metadata: metadata, summary: summary, groups: licence_group_aggregates,
          announcements: announcements_by_parish_and_classification, parishes: parish_totals, metrics: registration_metrics}))
        snapshot = PublicSnapshot.from_legacy(**inputs.transform_keys(&:to_sym))
        PublicSnapshot::Validator.new.validate!(snapshot, expected_run_id: metadata.fetch(:run_id), schema: PublicSnapshot::SCHEMA_VERSION, local: @mode == "local")
        snapshot
      end

      private

      def build_metadata
        source_dates = AlojamentoLocal.dates(listings).merge(@sources.source_dates)
        provenance = @sources.provenance.merge(source_dates: source_dates)
        commit, = Open3.capture2("git", "rev-parse", "HEAD")
        changes, = Open3.capture2("git", "status", "--porcelain", "--untracked-files=no")
        {
          run_id: @run_id,
          **provenance,
          git_commit: commit.strip, git_worktree_dirty: !changes.empty?, analysis_version: ANALYSIS_VERSION,
          methodology_version: METHODOLOGY_VERSION, output_schema_version: OUTPUT_SCHEMA_VERSION, mode: @mode
        }
      end
    end
  end
end
