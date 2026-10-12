# frozen_string_literal: true

require_relative "../analysis"

module AlojamentoLocal
  module Analysis
    class Runner
      def self.run(mode: "local", force: false, reuse_existing: false, generate_pdf: false)
        Analysis.validate_options!(mode: mode, force: force, reuse_existing: reuse_existing)

        airbnb_path, official_path = Data.prepare!
        if reuse_existing
          existing = Analysis.existing_public_run(airbnb_path: airbnb_path, official_path: official_path)
          return existing.merge(reused: true) if existing
        end

        Analysis.run(airbnb_path: airbnb_path, official_path: official_path,
          mode: mode, force: force, generate_pdf: generate_pdf).merge(reused: false)
      end
    end
  end
end
