# frozen_string_literal: true

module AlojamentoLocal
  module Analysis
    module_function

    def run(airbnb_path: nil, official_path: nil, output_root: "data/snapshots", history_path: "data/history/summary.csv", private_root: File.join(File.dirname(output_root), "private"))
      sources = PreparedSources::Pair.new(airbnb_path: airbnb_path, official_path: official_path)
      raise "No observed Lisbon announcements" if sources.airbnb.entries.empty?

      run_id = sources.identifier
      destination = File.join(output_root, run_id)
      private_path = File.join(private_root, run_id)
      validate_destinations!(output_root, private_root, history_path)
      PublicPublisher.verify_public_sources!(destination, sources.source_hashes) if Dir.exist?(destination)
      result = Result.new(sources: sources, run_id: run_id)
      result.summary[:historical_comparisons] = History.historical_comparisons(history_path, result.summary)
      sources.verify_unchanged!

      PublicPublisher.new(destination: destination, history_path: history_path, private_path: private_path).publish(
        summary: result.summary, listings: result.listings
      ) do |path, diagnostics|
        OutputWriter.new(result: result, path: path).generate_data
        OutputWriter.new(result: result, path: diagnostics).generate_diagnostics
      end
      {run_id: run_id, path: destination, private_path: private_path, summary: result.summary}
    end

    def validate_destinations!(output_root, private_root, history_path)
      public_paths = [output_root, File.dirname(history_path), "site", "_site", File.expand_path("../../_site", __dir__), File.expand_path("../../site", __dir__)]
      private_path = File.expand_path(private_root)
      public_paths.each do |path|
        path = File.expand_path(path)
        if path == private_path || path.start_with?(private_path + "/") || private_path.start_with?(path + "/")
          raise ArgumentError, "Private diagnostics must be separate from snapshots, history and site directories"
        end
      end
    end

    private_class_method :validate_destinations!
  end
end
