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

      def initialize(sources:, run_id:)
        @sources = sources
        @run_id = run_id
        @listings, = Classifier.new(sources).classify
        @metadata = build_metadata
        @licence_groups = Aggregates.licence_groups(listings)
        @summary = Aggregates.summary(listings, licence_groups, metadata.fetch(:source_dates),
          metadata.fetch(:run_id), official: sources.official)
        @registration_metrics = RegistrationMetrics.calculate(listings, sources.official).merge(
          run_id: metadata.fetch(:run_id), source_files: metadata.fetch(:source_files),
          methodology_version: metadata.fetch(:methodology_version), source_dates: metadata.fetch(:source_dates)
        )
        @parish_totals = Aggregates.freguesia_rows(listings)
        @announcements_by_parish_and_classification = Aggregates.public_listing_rows(listings)
        @licence_group_aggregates = Aggregates.public_group_rows(licence_groups)
      end

      def snapshot
        data = JSON.parse(JSON.generate({schema_version: OUTPUT_SCHEMA_VERSION,
          metadata: metadata, summary: summary, licence_group_aggregates: licence_group_aggregates,
          announcements_by_parish_and_classification: announcements_by_parish_and_classification,
          parish_totals: parish_totals, registration_metrics: registration_metrics}))
        PublicSnapshot.validate!(data, expected_run_id: @run_id)
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
          methodology_version: METHODOLOGY_VERSION, output_schema_version: OUTPUT_SCHEMA_VERSION
        }
      end
    end
  end
end
