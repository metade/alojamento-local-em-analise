# frozen_string_literal: true

module AlojamentoLocal
  module Analysis
    # Orchestrates a run; Runner holds its prepared data and publication state.

    module_function

    def run(airbnb_path: nil, official_path: nil, output_root: nil, history_path: nil, generate_pdf: false, mode: "local")
      raise ArgumentError, "Mode must be public or local" unless %w[public local].include?(mode)

      sources = PreparedSources::Pair.new(airbnb_path: airbnb_path, official_path: official_path)
      runner = Runner.new(sources: sources, mode: mode)
      runner.prepare_analysis(output_root: output_root, history_path: history_path)
      runner.publish do
        if runner.public?
          runner.generate_snapshot
        else
          runner.generate_local_outputs
        end
        runner.generate_report
        runner.generate_pdf if generate_pdf
      end
      runner.result
    end
  end
end
