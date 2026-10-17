require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "support/pipeline_fixture"
require_relative "support/jekyll_build"

class PublicSnapshotTest < Minitest::Test
  RUN_ID = PipelineFixture::RUN_ID

  def with_snapshot
    Dir.mktmpdir("public-snapshot-") do |root|
      path = File.join(root, RUN_ID)
      FileUtils.mkdir_p(path)
      data = JSON.parse(File.read(File.join(PipelineFixture::EXPECTED, "public", "snapshot.json")))
      data.fetch("metadata")["git_worktree_dirty"] = false
      data.fetch("summary")["generated_at"] = "2024-07-01T12:00:00Z"
      File.write(File.join(path, "snapshot.json"), JSON.generate(data))
      yield root, path
    end
  end

  def mutate(path)
    file = File.join(path, "snapshot.json")
    data = JSON.parse(File.read(file))
    yield data
    File.write(file, JSON.generate(data))
  end

  def test_load_returns_the_document_with_integer_counts
    with_snapshot do |_, path|
      document = AlojamentoLocal::PublicSnapshot.load(path)
      assert_equal JSON.parse(File.read(File.join(path, "snapshot.json"))), document
      assert_equal 34, document.fetch("announcements_by_parish_and_classification").sum { |row| row.fetch("announcements") }
      assert_equal 30, document.fetch("parish_totals").sum { |row| row.fetch("announcements_with_identifiable_number") }
      assert_equal 18, document.fetch("licence_group_aggregates").sum { |row| row.fetch("licence_groups") }
      assert_equal 28, document.fetch("summary").fetch("establishment_estimate")
      refute_equal 28, document.fetch("parish_totals").sum { |row| row.fetch("estimated_establishments") }
    end
  end

  def test_load_run_resolves_and_validates_the_selected_snapshot
    with_snapshot do |root, path|
      assert_equal AlojamentoLocal::PublicSnapshot.load(path),
        AlojamentoLocal::PublicSnapshot.load_run(RUN_ID, snapshots: root)
      mutate(path) { |data| data["summary"]["listings"] += 1 }
      assert_raises(RuntimeError) { AlojamentoLocal::PublicSnapshot.load_run(RUN_ID, snapshots: root) }
    end
  end

  def test_current_schema_preserves_previous_methodology_without_relabelling
    with_snapshot do |_, path|
      mutate(path) do |data|
        %w[metadata summary registration_metrics].each { |key| data[key]["methodology_version"] = "2.1.0" }
      end
      document = AlojamentoLocal::PublicSnapshot.load(path)
      assert_equal "2.1.0", document.fetch("metadata").fetch("methodology_version")
      assert_equal 28, document.fetch("summary").fetch("establishment_estimate")
      mutate(path) { |data| data["registration_metrics"]["methodology_version"] = "2.2.0" }
      assert_raises(RuntimeError) { AlojamentoLocal::PublicSnapshot.load(path) }
    end
  end

  def test_load_run_rejects_invalid_and_unknown_identifiers
    with_snapshot do |root, _|
      ["invalid", "../#{RUN_ID}"].each do |run_id|
        error = assert_raises(ArgumentError) { AlojamentoLocal::PublicSnapshot.load_run(run_id, snapshots: root) }
        assert_includes error.message, "Invalid public run ID"
      end
      error = assert_raises(RuntimeError) do
        AlojamentoLocal::PublicSnapshot.load_run("2024-01-01__2024-02-01", snapshots: root)
      end
      assert_includes error.message, "Unknown public run ID"
    end
  end

  def test_consumers_reject_schema_provenance_and_accounting_corruption
    mutations = {
      "version" => ->(d) { d["schema_version"] = "99.0.0" },
      "metadata version" => ->(d) { d["metadata"]["output_schema_version"] = "5.0.0" },
      "local mode" => ->(d) { %w[metadata summary].each { |key| d[key]["mode"] = "local" } },
      "local rerun identifier" => ->(d) { %w[metadata summary registration_metrics].each { |key| d[key]["run_id"] += "__rerun-20241014T123456123456" } },
      "unexpected field" => ->(d) { d["host_id"] = 123 },
      "nested private field" => ->(d) { d["parish_totals"][0]["licensa_raw"] = "123/AL" },
      "summary private field" => ->(d) { d["summary"]["name"] = "Private name" },
      "local source path" => ->(d) { d["metadata"]["source_files"]["airbnb"]["path"] = "/tmp/source.csv" },
      "source hash" => ->(d) { d["registration_metrics"]["source_files"]["official"]["sha256"] = "0" * 64 },
      "summary dates" => ->(d) { d["summary"]["source_dates"]["official_register_date"] = "2020-02-01" },
      "invalid date" => ->(d) { d["metadata"]["source_dates"]["airbnb_snapshot_date"] = "2024-02-31" },
      "old methodology" => ->(d) { %w[metadata summary registration_metrics].each { |key| d[key]["methodology_version"] = "2.0.0" } },
      "summary counts" => ->(d) { d["summary"]["licence_groups"] += 1 },
      "classifications" => ->(d) { d["summary"]["classifications"]["sem licença"] = 1 },
      "noninteger count" => ->(d) { d["licence_group_aggregates"][0]["announcements"] = "6" },
      "negative count" => ->(d) { d["licence_group_aggregates"][0]["licence_groups"] = -1 },
      "duplicate aggregate" => ->(d) { d["parish_totals"] << d["parish_totals"][0] },
      "parish totals" => ->(d) { d["parish_totals"][0]["announcements"] += 1 },
      "classification announcements" => ->(d) { d["announcements_by_parish_and_classification"][0]["classification"] = "sem licença" },
      "city estimate" => ->(d) { d["summary"]["establishment_estimate"] += 1 },
      "official entries" => ->(d) { d["registration_metrics"]["rows"][1]["official_entries"] += 1 },
      "missing metric field" => ->(d) { d["registration_metrics"]["rows"][0].delete("rnal") },
      "uppercase URL" => ->(d) { d["licence_group_aggregates"][0]["official_type"] = "HTTPS://example.invalid/ROOMS/123" },
      "listing URL" => ->(d) { d["licence_group_aggregates"][0]["official_type"] = "https://example.invalid/rooms/123" }
    }
    mutations.each do |name, change|
      with_snapshot do |root, path|
        mutate(path, &change)
        before = File.binread(File.join(path, "snapshot.json"))
        error = assert_raises(RuntimeError, name) { AlojamentoLocal::PublicSnapshot.load(path) }
        assert_equal before, File.binread(File.join(path, "snapshot.json")), name
      end
    end
  end

  def test_only_current_schema_is_supported_and_missing_or_broken_documents_fail
    with_snapshot do |root, path|
      original = File.read(File.join(path, "snapshot.json"))
      %w[4.0.0 5.0.0 6.0.0].each do |version|
        File.write(File.join(path, "snapshot.json"), original)
        mutate(path) { |data| data["schema_version"] = data["metadata"]["output_schema_version"] = version }
        assert_raises(RuntimeError) { AlojamentoLocal::PublicSnapshot.load(path) }
      end
      File.write(File.join(path, "snapshot.json"), "{")
      assert_raises(JSON::ParserError) { AlojamentoLocal::PublicSnapshot.load(path) }
      FileUtils.rm(File.join(path, "snapshot.json"))
      File.write(File.join(path, "metadata.json"), "{}")
      assert_raises(Errno::ENOENT) { AlojamentoLocal::PublicSnapshot.load(path) }
    end
  end

  def test_publication_needs_only_snapshot_and_source_hash_guard_remains
    with_snapshot do |_, path|
      snapshot = AlojamentoLocal::PublicSnapshot.load(path)
      hashes = %w[airbnb official].map { |source| snapshot.fetch("metadata").fetch("source_files").fetch(source).fetch("sha256") }
      assert_equal ["snapshot.json"], Dir.children(path)
      AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, hashes)
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, ["0" * 64, hashes.last]) }
      FileUtils.cp(File.expand_path("../NOTICE", __dir__), File.join(path, "NOTICE"))
      output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", path)
      assert status.success?, output
      mutate(path) { |data| data["summary"]["listings"] += 1 }
      assert_raises(RuntimeError) { AlojamentoLocal::Analysis::PublicPublisher.verify_public_sources!(path, hashes) }
    end
  end
end
