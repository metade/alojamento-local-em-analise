require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/alojamento_local"
require_relative "../lib/alojamento_local/site_data"

class PublicSnapshotTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/pipeline/expected/public", __dir__)
  RUN_ID = "2024-06-01__2024-07-01"

  def with_snapshot
    Dir.mktmpdir("public-snapshot-") do |root|
      path = File.join(root, RUN_ID)
      FileUtils.cp_r(FIXTURE, path)
      %w[summary.json report.html].each do |file|
        target = File.join(path, file)
        File.write(target, File.read(target).gsub("<generated_at>", "2024-07-01T12:00:00Z"))
      end
      yield root, path
    end
  end

  def mutate_json(path, file)
    data = JSON.parse(File.read(File.join(path, file)))
    yield data
    File.write(File.join(path, file), JSON.generate(data))
  end

  def mutate_csv(path, file)
    table = CSV.read(File.join(path, file), headers: true)
    yield table
    File.write(File.join(path, file), table.to_csv)
  end

  def test_typed_units_immutable_inputs_and_byte_identical_report
    with_snapshot do |_, path|
      loader = AlojamentoLocal::PublicSnapshot::Loader.new
      snapshot = loader.load(path)
      assert_same snapshot, loader.load(path)
      assert_equal RUN_ID, snapshot.run_id
      assert_equal 34, snapshot.announcements_by_parish_and_classification.sum { |row| row.fetch("announcements") }
      assert_equal 30, snapshot.parish_totals.sum { |row| row.fetch("announcements_with_identifiable_number") }
      assert_equal 18, snapshot.licence_group_aggregates.sum { |row| row.fetch("licence_groups") }
      # Parish estimates and distinct numbers are intentionally nonadditive.
      assert_equal 28, snapshot.summary.fetch("establishment_estimate")
      refute_equal 28, snapshot.parish_totals.sum { |row| row.fetch("estimated_establishments") }
      refute_equal snapshot.registration_metrics.fetch("rows").first.fetch("airbnb"), snapshot.registration_metrics.fetch("rows").drop(1).sum { |row| row.fetch("airbnb") }
      assert_raises(FrozenError) { snapshot.registration_metrics.fetch("rows").first["airbnb"] = 0 }
      assert_equal File.read(File.join(path, "report.html")), AlojamentoLocal::Report.complete_html(*snapshot.report_arguments)
      assert_equal CSV.read(File.join(path, "listings.csv"), headers: true).map(&:to_h), snapshot.published_announcement_rows
    end
  end

  def test_consumers_reject_schema_provenance_and_aggregate_corruption
    mutations = {
      "schema version" => ->(path) { mutate_json(path, "metadata.json") { |data| data["output_schema_version"] = "99.0.0" } },
      "summary dates" => ->(path) { mutate_json(path, "summary.json") { |data| data["source_dates"]["official_register_date"] = "2020-02-01" } },
      "metric dates" => ->(path) { mutate_json(path, "registration_metrics.json") { |data| data["source_dates"]["airbnb_snapshot_date"] = "2024-06-02" } },
      "summary counts" => ->(path) { mutate_json(path, "summary.json") { |data| data["licence_groups"] += 1 } },
      "classifications" => ->(path) { mutate_json(path, "summary.json") { |data| data["classifications"]["sem licença"] = 1 } },
      "CSV header" => ->(path) { file = File.join(path, "listings.csv"); File.write(file, File.read(file).sub("identifiable_licences", "distinct_licences")) },
      "noninteger count" => ->(path) { mutate_csv(path, "listings.csv") { |table| table[0]["listings"] = "1.5" } },
      "negative count" => ->(path) { mutate_csv(path, "licence_groups.csv") { |table| table[0]["licence_groups"] = "-1" } },
      "duplicate aggregate" => ->(path) { mutate_csv(path, "freguesias.csv") { |table| table << table[0] } },
      "parish totals" => ->(path) { mutate_csv(path, "freguesias.csv") { |table| table[0]["listings"] = "99" } },
      "classification announcements" => ->(path) { mutate_csv(path, "listings.csv") { |table| table[0]["classification"] = "sem licença" } },
      "city estimate" => ->(path) { mutate_json(path, "summary.json") { |data| data["establishment_estimate"] += 1 } },
      "official entries" => ->(path) { mutate_json(path, "registration_metrics.json") { |data| data["rows"][1]["official_entries"] += 1 } }
    }
    mutations.each do |name, mutate|
      with_snapshot do |root, path|
        mutate.call(path)
        before = Dir.children(path).to_h { |file| [file, File.binread(File.join(path, file))] }
        loader_error = assert_raises(RuntimeError, name) { AlojamentoLocal::PublicSnapshot::Loader.new.load(path) }
        builder = AlojamentoLocal::SiteData.new(snapshots: root)
        site_error = assert_raises(RuntimeError, name) { builder.site_data(builder.public_runs) }
        assert_equal loader_error.message, site_error.message, name
        output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/regenerate_public_report.rb", __dir__), path)
        refute status.success?, name
        assert_includes output, loader_error.message, name
        assert_equal before, Dir.children(path).to_h { |file| [file, File.binread(File.join(path, file))] }, name
      end
    end
  end

  def test_discovery_skips_unsupported_metrics_but_does_not_hide_corrupt_supported_runs
    with_snapshot do |root, path|
      newer = File.join(root, "2024-06-01__2024-08-01")
      FileUtils.cp_r(path, newer)
      mutate_json(newer, "metadata.json") { |data| data["source_dates"]["official_register_download_date"] = "2024-08-01" }
      FileUtils.rm(File.join(newer, "registration_metrics.json"))
      builder = AlojamentoLocal::SiteData.new(snapshots: root)
      assert_equal path, builder.measured_run(builder.public_runs)
      FileUtils.cp(File.join(path, "registration_metrics.json"), newer)
      builder = AlojamentoLocal::SiteData.new(snapshots: root)
      assert_equal newer, builder.measured_run(builder.public_runs)
      assert_raises(RuntimeError) { builder.site_data(builder.public_runs) }
    end
  end
end
