# frozen_string_literal: true

require "time"

module AlojamentoLocal
  module Analysis
    module_function

    def run(airbnb_path: nil, official_path: nil, output_root: nil, history_path: nil, generate_pdf: false, mode: "local")
      raise ArgumentError, "Mode must be public or local" unless %w[public local].include?(mode)
      sources = prepare_sources(airbnb_path: airbnb_path, official_path: official_path)
      run_id, destination, history_path = prepare_destination(sources, mode: mode, output_root: output_root, history_path: history_path)
      result = prepare_result(sources, run_id: run_id, mode: mode, history_path: history_path)

      publish(result, destination: destination, history_path: history_path, mode: mode) do |path|
        writer = OutputWriter.new(result: result, path: path)
        writer.generate_data
        writer.generate_report
        writer.generate_pdf if generate_pdf
      end
      {run_id: run_id, path: destination, summary: result.summary}
    end

    def prepare_sources(airbnb_path:, official_path:)
      sources = PreparedSources::Pair.new(airbnb_path: airbnb_path, official_path: official_path)
      raise "No observed Lisbon announcements" if sources.airbnb.entries.empty?

      sources
    end

    def prepare_destination(sources, mode:, output_root:, history_path:)
      output_root ||= (mode == "public") ? "data/snapshots" : "data/private"
      history_path ||= (mode == "public") ? "data/history/summary.csv" : "data/private/history/summary.csv"
      run_id = sources.identifier
      run_id = local_run_id(run_id, output_root) if mode == "local"
      destination = File.join(output_root, run_id)
      PublicPublisher.verify_public_sources!(destination, sources.source_hashes) if mode == "public" && Dir.exist?(destination)
      [run_id, destination, history_path]
    end

    def prepare_result(sources, run_id:, mode:, history_path:)
      result = Result.new(sources: sources, run_id: run_id, mode: mode)
      result.summary[:historical_comparisons] = History.historical_comparisons(history_path, result.summary)
      sources.verify_unchanged!
      History.verify_local_run!(history_path, run_id) if mode == "local"
      result
    end

    def publish(result, destination:, history_path:, mode:)
      if mode == "public"
        PublicPublisher.new(destination: destination, history_path: history_path).publish(
          summary: result.summary, listings: result.listings
        ) { |path| yield path }
      else
        yield destination
        History.append_history(history_path, result.summary)
      end
    end

    def local_run_id(base, output_root)
      return base unless Dir.exist?(File.join(output_root, base))

      rerun = "#{base}__rerun-#{Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")}"
      candidate = rerun
      increment = 2
      while Dir.exist?(File.join(output_root, candidate))
        candidate = "#{rerun}-#{increment}"
        increment += 1
      end
      candidate
    end

    private_class_method :prepare_sources, :prepare_destination, :prepare_result, :publish, :local_run_id
  end
end
