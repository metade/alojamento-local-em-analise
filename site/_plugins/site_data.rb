# frozen_string_literal: true

require_relative "../../lib/alojamento_local"

Jekyll::Hooks.register :site, :post_read, priority: :high do |site|
  next if ENV["REPORT_RUN"]
  builder = AlojamentoLocal::SiteData.new
  runs = builder.public_runs
  raise "Não existem snapshots públicos em #{AlojamentoLocal::SiteData::SNAPSHOTS}." if runs.empty?
  site.config["report_runs"] = runs
  site.data["site"] = builder.site_data(runs)
  selected = builder.measured_run(runs)
  if selected != runs.first
    Jekyll.logger.warn "Snapshots:", "Newest snapshot #{File.basename(runs.first)} lacks supported set metrics; site uses #{File.basename(selected)}"
  end
end
