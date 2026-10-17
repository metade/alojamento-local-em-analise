module AlojamentoLocal
  module Analysis
    module_function

    def run(airbnb_path: nil, official_path: nil, output_root: "data/snapshots")
      sources = DataSource.new(airbnb_path: airbnb_path, official_path: official_path)
      raise "No observed Lisbon listings" if sources.airbnb.entries.empty?
      dataset = DatasetBuilder.new(sources: sources).build
      destination = File.join(output_root, sources.identifier)
      ResultPublisher.new(destination: destination).publish(dataset: dataset, sources: sources)
      {run_id: sources.identifier, path: destination, summary: dataset.summary}
    end
  end
end
