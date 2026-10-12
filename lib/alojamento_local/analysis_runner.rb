# frozen_string_literal: true

require_relative "../alojamento_local"

module AlojamentoLocal
  class AnalysisRunner
    def self.run(mode: "local", force: false, reuse_existing: false, generate_pdf: false)
      raise ArgumentError, "Mode must be public or local" unless %w[public local].include?(mode)
      raise ArgumentError, "Force is only supported in local mode" if force && mode != "local"
      raise ArgumentError, "Reuse is only supported in public mode" if reuse_existing && mode != "public"

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
