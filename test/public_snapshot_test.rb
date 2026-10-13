require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/alojamento_local"

class PublicSnapshotTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/pipeline/legacy_public", __dir__)
  RUN_ID = "2024-06-01__2024-07-01"

  def with_snapshot
    Dir.mktmpdir("public-snapshot-") do |root|
      path = File.join(root, RUN_ID)
      FileUtils.cp_r(FIXTURE, path)
      FileUtils.rm_f(File.join(path, "snapshot.json"))
      metadata_path = File.join(path, "metadata.json")
      metadata = JSON.parse(File.read(metadata_path))
      metadata["output_schema_version"] = "4.0.0"
      File.write(metadata_path, JSON.pretty_generate(metadata) + "\n")
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
  def consolidate(path)
    legacy = AlojamentoLocal::PublicSnapshot::Loader.new.load(path)
    data = JSON.parse(JSON.generate(legacy.to_h))
    data["metadata"]["output_schema_version"] = "6.0.0"
    data["metadata"]["analysis_version"] = AlojamentoLocal::ANALYSIS_VERSION
    snapshot = AlojamentoLocal::PublicSnapshot.from_document(data)
    File.write(File.join(path, "snapshot.json"), JSON.pretty_generate(data) + "\n")
    File.write(File.join(path, "metadata.json"), JSON.pretty_generate(data.fetch("metadata")) + "\n")
    snapshot
  end

  def builder(root)
    history = File.expand_path("fixtures/pipeline/expected/public-history", __dir__)
    AlojamentoLocal::SiteData.new(snapshots: root,
      distance_history: File.join(history, "distance_ranges.csv"), outside_region_history: File.join(history, "outside_regions.csv"),
      quotes: File.expand_path("fixtures/pipeline/sources/quotes.json", __dir__))
  end

  def test_old_and_new_formats_have_equivalent_report_contents_and_site_data
    with_snapshot do |root, path|
      old = AlojamentoLocal::PublicSnapshot::Loader.new.load(path)
      old_site = builder(root).site_data([path])
      original_report = AlojamentoLocal::Report.complete_html(*old.report_arguments)
      new_snapshot = consolidate(path)
      new_site = builder(root).site_data([path])
      old_site = JSON.parse(JSON.generate(old_site))
      old_site["metadata"]["output_schema_version"] = "6.0.0"
      old_site["metadata"]["analysis_version"] = AlojamentoLocal::ANALYSIS_VERSION
      # Normalize the intentional version/reference changes, preserving tables.
      original_report = original_report.sub("análise 3.3.0", "análise #{AlojamentoLocal::ANALYSIS_VERSION}")
        .sub("<code>metadata.json</code>", "<a href='snapshot.json'>snapshot.json</a>")
        .sub("unidades e definições em registration_metrics.json", "unidades e definições em snapshot.json")
      assert_equal old_site, new_site
      assert_equal original_report, AlojamentoLocal::Report.complete_html(*new_snapshot.report_arguments)
      File.write(File.join(path, "report.html"), "Incomplete report")
      output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/regenerate_public_report.rb", __dir__), path)
      assert status.success?, output
      assert_equal original_report, File.read(File.join(path, "report.html"))
      (AlojamentoLocal::PublicSnapshot::FIELDS - ["metadata"]).each do |field|
        assert_equal old.public_send(field), new_snapshot.public_send(field), field
      end
    end
  end

  def test_consolidated_document_and_report_are_sufficient_for_publication
    with_snapshot do |root, path|
      snapshot = consolidate(path)
      expected = builder(root).site_data([path])
      %w[metadata.json summary.json registration_metrics.json listings.csv licence_groups.csv freguesias.csv].each { |file| FileUtils.rm(File.join(path, file)) }
      assert_equal %w[report.html snapshot.json], Dir.children(path).sort
      assert_equal expected, builder(root).site_data([path])
      assert_equal snapshot.to_h, AlojamentoLocal::PublicSnapshot::Loader.new.load(path).to_h
      FileUtils.cp(File.expand_path("../NOTICE", __dir__), File.join(path, "NOTICE"))
      output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", path)
      assert status.success?, output
    end
  end

  def test_invalid_consolidated_documents_never_fall_back_to_valid_exports
    mutations = {
      "version" => ->(data) { data["schema_version"] = "99.0.0" },
      "unexpected field" => ->(data) { data["host_id"] = 123 },
      "unexpected summary field" => ->(data) { data["summary"]["name"] = "Private name" },
      "wrong source" => ->(data) { data["registration_metrics"]["source_files"]["official"]["sha256"] = "0" * 64 },
      "invalid aggregate" => ->(data) { data["parish_totals"][0]["announcements"] += 1 },
      "integer type" => ->(data) { data["licence_group_aggregates"][0]["announcements"] = "6" },
      "raw nested field" => ->(data) { data["announcements_by_parish_and_classification"][0]["licensa_raw"] = "123/AL" }
    }
    mutations.each do |name, mutate|
      with_snapshot do |root, path|
        consolidate(path)
        mutate_json(path, "snapshot.json", &mutate)
        before = File.binread(File.join(path, "report.html"))
        assert_raises(RuntimeError, name) { AlojamentoLocal::PublicSnapshot::Loader.new.load(path) }
        assert_raises(RuntimeError, name) { builder(root).site_data([path]) }
        output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/regenerate_public_report.rb", __dir__), path)
        refute status.success?, output
        assert_equal before, File.binread(File.join(path, "report.html"))
      end
    end
    with_snapshot do |_, path|
      consolidate(path)
      File.write(File.join(path, "snapshot.json"), "{")
      assert_raises(JSON::ParserError) { AlojamentoLocal::PublicSnapshot::Loader.new.load(path) }
      FileUtils.rm(File.join(path, "snapshot.json"))
      assert_raises(RuntimeError) { AlojamentoLocal::PublicSnapshot::Loader.new.load(path) }
    end
  end

  def test_source_hash_guard_uses_authoritative_document_without_exports_or_report
    with_snapshot do |_, path|
      snapshot = consolidate(path)
      hashes = %w[airbnb official].map { |source| snapshot.metadata.fetch("source_files").fetch(source).fetch("sha256") }
      %w[metadata.json summary.json registration_metrics.json listings.csv licence_groups.csv freguesias.csv].each { |file| FileUtils.rm(File.join(path, file)) }
      AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, hashes)
      FileUtils.rm(File.join(path, "report.html"))
      AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, hashes)
      File.write(File.join(path, "report.html"), AlojamentoLocal::Report.complete_html(*snapshot.report_arguments))
      mutate_json(path, "snapshot.json") { |data| data["summary"]["listings"] += 1 }
      assert_raises(RuntimeError) { AlojamentoLocal::PublicSnapshot::Loader.new.load(path) }
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, ["0" * 64, hashes.last]) }
    end
  end

  def test_previous_consolidated_schema_loads_without_its_exports
    with_snapshot do |_, path|
      snapshot = consolidate(path)
      data = JSON.parse(JSON.generate(snapshot.to_h))
      data["schema_version"] = data["metadata"]["output_schema_version"] = "5.0.0"
      File.write(File.join(path, "snapshot.json"), JSON.generate(data))
      %w[metadata.json summary.json registration_metrics.json listings.csv licence_groups.csv freguesias.csv].each { |file| FileUtils.rm(File.join(path, file)) }
      loaded = AlojamentoLocal::PublicSnapshot::Loader.new.load(path)
      assert_equal data, loaded.to_h
      assert_equal snapshot.registration_metrics, loaded.registration_metrics
      hashes = %w[airbnb official].map { |source| loaded.metadata.fetch("source_files").fetch(source).fetch("sha256") }
      AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, hashes)
    end
  end

end
