require_relative "../../lib/alojamento_local"

module CandidateFixture
  PATH = File.expand_path("../fixtures/pipeline/snapshots/candidate", __dir__)

  def self.dataset
    AlojamentoLocal::CandidateDataset.new(PATH)
  end
end
