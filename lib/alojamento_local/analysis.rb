# frozen_string_literal: true

module AlojamentoLocal
  module Analysis
    # Orchestrates a run; Runner holds its prepared data and publication state.
    # The remaining entry points preserve existing helper interfaces.

    module_function

    def run(airbnb_path: nil, official_path: nil, output_root: nil, history_path: nil, generate_pdf: false, mode: "local")
      runner = Runner.new(airbnb_path: airbnb_path, official_path: official_path, mode: mode)
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

    def analyse(airbnb_path, official_path)
      classify(PreparedSources::Pair.new(airbnb_path: airbnb_path, official_path: official_path))
    end

    def classify(sources)
      Classifier.new(sources).classify
    end

    def licence_groups(listings, _official)
      Aggregates.licence_groups(listings)
    end

    def public_listing_rows(listings)
      Aggregates.public_listing_rows(listings)
    end

    def public_group_rows(groups)
      Aggregates.public_group_rows(groups)
    end

    def public_municipality(value)
      Aggregates.public_municipality(value)
    end

    def public_type(value)
      Aggregates.public_type(value)
    end

    def freguesia_rows(listings)
      Aggregates.freguesia_rows(listings)
    end

    def summary(listings, groups, dates, run_id, mode, official: {})
      Aggregates.summary(listings, groups, dates, run_id, mode, official: official)
    end

    def append_history(path, row, replace: false)
      History.append_history(path, row, replace: replace)
    end

    def write_history_rows(path, headers, run_id, rows, replace: false)
      History.write_history_rows(path, headers, run_id, rows, replace: replace)
    end

    def distance_range_counts(listings)
      History.distance_range_counts(listings)
    end

    def append_distance_history(path, run_id, listings, replace: false)
      History.append_distance_history(path, run_id, listings, replace: replace)
    end

    def outside_region_counts(listings)
      History.outside_region_counts(listings)
    end

    def append_outside_region_history(path, run_id, listings, replace: false)
      History.append_outside_region_history(path, run_id, listings, replace: replace)
    end

    def historical_comparisons(path, current)
      History.historical_comparisons(path, current)
    end

    def write_outputs(run_dir:, mode:, listings:, groups:, freguesias:, public_listings:, public_groups:, metadata:, summary:, metrics:)
      OutputWriter.write_outputs(run_dir: run_dir, mode: mode, listings: listings, groups: groups,
        freguesias: freguesias, public_listings: public_listings, public_groups: public_groups,
        metadata: metadata, summary: summary, metrics: metrics)
    end

    def detailed_listing_rows(listings)
      OutputWriter.detailed_listing_rows(listings)
    end

    def detailed_group_rows(groups)
      OutputWriter.detailed_group_rows(groups)
    end

    def write_json_outputs(run_dir, metadata, summary, metadata_filename, summary_filename)
      OutputWriter.write_json_outputs(run_dir, metadata, summary, metadata_filename, summary_filename)
    end

    def write_csv(path, rows)
      OutputWriter.write_csv(path, rows)
    end

    def generate_pdf_file(run_dir)
      OutputWriter.generate_pdf_file(run_dir)
    end

    def validate_options!(mode:)
      Runner.validate_options!(mode: mode)
    end

    def verify_public_sources!(path, hashes)
      PublicPublisher.verify_public_sources!(path, hashes)
    end

    def publish_public_run!(staged_run, destination, histories, staging)
      PublicPublisher.publish_public_run!(staged_run, destination, histories, staging)
    end

    def validate_public_outputs!(run_dir)
      PublicPublisher.validate_public_outputs!(run_dir)
    end

    def metadata(airbnb, official, dates, run_id, mode)
      Runner.metadata(airbnb, official, dates, run_id, mode)
    end

    def parse_date(value)
      Classifier.parse_date(value)
    end

    def status(record, distance, count)
      Classifier.status(record, distance, count)
    end
  end
end
