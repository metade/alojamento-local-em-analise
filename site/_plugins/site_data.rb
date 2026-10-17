# frozen_string_literal: true

require_relative "../../lib/alojamento_local"

Jekyll::Hooks.register :site, :post_read, priority: :high do |site|
  path = ENV["REPORT_RUN"] || ENV["SNAPSHOT"] || site.config["snapshot"] || AlojamentoLocal::CandidateDataset.default_path
  dataset = AlojamentoLocal::CandidateDataset.new(File.expand_path(path, AlojamentoLocal::SiteData::ROOT))
  site.config["candidate_dataset"] = dataset
  site.data["site"] = AlojamentoLocal::SiteData.new(dataset: dataset).site_data
end
