require_relative "../../lib/alojamento_local"

module CandidateFixture
  PATH = File.expand_path("../fixtures/pipeline/snapshots/candidate", __dir__)

  def self.documents(dataset)
    JSON.parse(JSON.generate(dataset.summary_document.merge(dataset.details_document)))
  end

  def self.from_documents(doc, refresh: false)
    summary = doc.reject { |key, _| %w[candidates grouping_assessments].include?(key) }
    if refresh
      aggregates = AlojamentoLocal::CandidateDataset.candidate_aggregates(doc.fetch("candidates"))
      summary["lisbon"].merge!(aggregates.delete("lisbon"))
      summary["parishes"].zip(aggregates.delete("parishes")).each { |row, counts| row.merge!(counts) }
      summary.merge!(aggregates)
    end
    AlojamentoLocal::CandidateDataset.new(summary_document: summary, details_document: doc.slice("candidates", "grouping_assessments"))
  end

  def self.dataset
    AlojamentoLocal::CandidateDataset.new(PATH)
  end
end
