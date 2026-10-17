module AlojamentoLocal
  module Analysis
    module_function

    def run(airbnb_path: nil, official_path: nil, output_root: "data/snapshots")
      sources = DataSource.new(airbnb_path: airbnb_path, official_path: official_path)
      raise "No observed Lisbon listings" if sources.airbnb.entries.empty?
      result = Result.new(sources: sources)
      destination = File.join(output_root, sources.identifier)
      ResultPublisher.new(destination: destination).publish(result: result, sources: sources)
      {run_id: sources.identifier, path: destination, summary: result.summary}
    end
  end
end
