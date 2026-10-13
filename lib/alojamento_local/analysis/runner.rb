# frozen_string_literal: true

require "csv"
require "date"
require "digest"
require "fileutils"
require "open3"
require "time"

module AlojamentoLocal
  module Analysis
    class Runner
      def initialize(airbnb_path: nil, official_path: nil, mode: "local")
        self.class.validate_options!(mode: mode)
        raise ArgumentError, "Provide both source paths or neither" if airbnb_path.nil? != official_path.nil?

        @airbnb_path, @official_path = airbnb_path.nil? ? Data.local_paths! : [airbnb_path, official_path]
        @mode = mode
      end

      def prepare_analysis(output_root: nil, history_path: nil)
        @output_root = output_root || (public? ? "data/snapshots" : "data/private")
        @history_path = history_path || (public? ? "data/history/summary.csv" : "data/private/history/summary.csv")
        @source_hashes = source_hashes
        sources = PreparedSources::Pair.new(airbnb_path: @airbnb_path, official_path: @official_path)
        listings, = Classifier.new(sources).classify
        raise "No observed Lisbon announcements" if listings.empty?

        dates = source_dates(listings)
        @run_id = select_run_id(dates)
        @destination = File.join(@output_root, @run_id)
        @outputs = calculate_outputs(sources, listings, dates, @run_id)
        verify_sources_unchanged!
        History.verify_local_run!(@history_path, @run_id) unless public?
      end

      def public?
        @mode == "public"
      end

      def publish
        if public?
          PublicPublisher.new(destination: @destination, history_path: @history_path).publish(
            summary: @outputs.fetch(:summary), listings: @outputs.fetch(:listings)
          ) do |run_dir|
            @run_dir = run_dir
            FileUtils.mkdir_p(@run_dir)
            yield
          end
        else
          @run_dir = @destination
          FileUtils.mkdir_p(@run_dir)
          yield
          History.append_history(@history_path, @outputs.fetch(:summary))
        end
      ensure
        @run_dir = nil
      end

      def generate_snapshot
        @snapshot = OutputWriter.write_public_snapshot(@run_dir, @outputs.fetch(:metadata), @outputs.fetch(:summary),
          @outputs.fetch(:public_groups), @outputs.fetch(:public_listings), @outputs.fetch(:freguesias), @outputs.fetch(:metrics))
      end

      def generate_local_outputs
        OutputWriter.write_local_outputs(@run_dir, @outputs.fetch(:metadata), @outputs.fetch(:summary),
          @outputs.fetch(:listings), @outputs.fetch(:groups), @outputs.fetch(:freguesias), @outputs.fetch(:metrics))
      end

      def generate_report
        filename = public? ? "report.html" : "report_local.html"
        arguments = if public?
          @snapshot.report_arguments
        else
          @outputs.values_at(:metadata, :summary, :public_groups, :public_listings, :metrics)
        end
        OutputWriter.write_report(@run_dir, filename, arguments)
      end

      def generate_pdf
        OutputWriter.generate_pdf_file(@run_dir)
      end

      def result
        {run_id: @run_id, path: @destination, summary: @outputs.fetch(:summary)}
      end

      def self.validate_options!(mode:)
        raise ArgumentError, "Mode must be public or local" unless %w[public local].include?(mode)
      end

      def self.metadata(airbnb, official, dates, run_id, mode, hashes: nil)
        hashes ||= [airbnb, official].map { |path| Digest::SHA256.file(path).hexdigest }
        commit, = Open3.capture2("git", "rev-parse", "HEAD")
        changes, = Open3.capture2("git", "status", "--porcelain", "--untracked-files=no")
        {
          run_id: run_id,
          source_urls: {airbnb: Data.airbnb_url(dates[:airbnb_snapshot_date]), official: Data::OFFICIAL_URL},
          source_dates: dates, source_files: {airbnb: {sha256: hashes[0]}, official: {sha256: hashes[1]}},
          git_commit: commit.strip, git_worktree_dirty: !changes.empty?, analysis_version: ANALYSIS_VERSION,
          methodology_version: METHODOLOGY_VERSION, output_schema_version: OUTPUT_SCHEMA_VERSION, mode: mode
        }
      end

      private

      def source_hashes
        [@airbnb_path, @official_path].map { |path| Digest::SHA256.file(path).hexdigest }
      end

      def verify_sources_unchanged!
        raise "Source bytes changed during analysis" unless @source_hashes == source_hashes
      end

      def source_dates(listings)
        dates = AlojamentoLocal.dates(listings)
        dates[:airbnb_snapshot_date] = filename_date(@airbnb_path) || dates[:airbnb_snapshot_date]
        dates[:official_register_download_date] = filename_date(@official_path) || File.mtime(@official_path).to_date.to_s
        dates
      end

      def filename_date(path)
        File.basename(path)[/(\d{4}-\d{2}-\d{2})/, 1]
      end

      def select_run_id(dates)
        base = "#{dates[:airbnb_snapshot_date]}__#{dates[:official_register_download_date]}"
        destination = File.join(@output_root, base)
        if public?
          PublicPublisher.verify_public_sources!(destination, @source_hashes) if Dir.exist?(destination)
          base
        else
          local_run_id(base)
        end
      end

      def local_run_id(base)
        return base unless Dir.exist?(File.join(@output_root, base))

        rerun = "#{base}__rerun-#{Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")}"
        candidate = rerun
        increment = 2
        while Dir.exist?(File.join(@output_root, candidate))
          candidate = "#{rerun}-#{increment}"
          increment += 1
        end
        candidate
      end

      def calculate_outputs(sources, listings, dates, run_id)
        groups = Aggregates.licence_groups(listings)
        summary = Aggregates.summary(listings, groups, dates, run_id, @mode, official: sources.official)
        summary[:historical_comparisons] = History.historical_comparisons(@history_path, summary)
        metadata = self.class.metadata(@airbnb_path, @official_path, dates, run_id, @mode, hashes: @source_hashes)
        metrics = RegistrationMetrics.calculate(listings, sources.official).merge(
          run_id: run_id, source_files: metadata[:source_files], methodology_version: METHODOLOGY_VERSION, source_dates: dates
        )
        {
          listings: listings, groups: groups, freguesias: Aggregates.freguesia_rows(listings),
          public_listings: Aggregates.public_listing_rows(listings), public_groups: Aggregates.public_group_rows(groups),
          metadata: metadata, summary: summary, metrics: metrics
        }
      end
    end
  end
end
