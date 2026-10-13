# frozen_string_literal: true

require "fileutils"
require "time"

module AlojamentoLocal
  module Analysis
    class Runner
      def initialize(sources:, mode: "local")
        @sources = sources
        @mode = mode
      end

      def prepare_analysis(output_root: nil, history_path: nil)
        @output_root = output_root || (public? ? "data/snapshots" : "data/private")
        @history_path = history_path || (public? ? "data/history/summary.csv" : "data/private/history/summary.csv")
        raise "No observed Lisbon announcements" if @sources.airbnb.entries.empty?

        @run_id = select_run_id(@sources)
        @destination = File.join(@output_root, @run_id)
        @analysis_result = Result.new(sources: @sources, run_id: @run_id, mode: @mode)
        @analysis_result.summary[:historical_comparisons] = History.historical_comparisons(@history_path, @analysis_result.summary)
        @sources.verify_unchanged!
        History.verify_local_run!(@history_path, @run_id) unless public?
      end

      def public?
        @mode == "public"
      end

      def publish
        if public?
          PublicPublisher.new(destination: @destination, history_path: @history_path).publish(
            summary: @analysis_result.summary, listings: @analysis_result.listings
          ) do |run_dir|
            @run_dir = run_dir
            FileUtils.mkdir_p(@run_dir)
            yield
          end
        else
          @run_dir = @destination
          FileUtils.mkdir_p(@run_dir)
          yield
          History.append_history(@history_path, @analysis_result.summary)
        end
      ensure
        @run_dir = nil
      end

      def generate_snapshot
        @snapshot = @analysis_result.public_snapshot
        OutputWriter.write_snapshot(@run_dir, @snapshot)
      end

      def generate_local_outputs
        OutputWriter.write_local_outputs(@run_dir, @analysis_result)
      end

      def generate_report
        filename = public? ? "report.html" : "report_local.html"
        arguments = if public?
          @snapshot.report_arguments
        else
          @analysis_result.report_arguments
        end
        OutputWriter.write_report(@run_dir, filename, arguments)
      end

      def generate_pdf
        OutputWriter.generate_pdf_file(@run_dir)
      end

      def result
        {run_id: @run_id, path: @destination, summary: @analysis_result.summary}
      end

      private

      def select_run_id(sources)
        dates = sources.source_dates
        base = "#{dates[:airbnb_snapshot_date]}__#{dates[:official_register_download_date]}"
        destination = File.join(@output_root, base)
        if public?
          PublicPublisher.verify_public_sources!(destination, sources.source_hashes) if Dir.exist?(destination)
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
    end
  end
end
