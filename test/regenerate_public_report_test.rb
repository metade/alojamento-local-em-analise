require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "json"

class RegeneratePublicReportTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/pipeline/expected/public", __dir__)
  SCRIPT = File.expand_path("../scripts/regenerate_public_report.rb", __dir__)

  def with_snapshot
    Dir.mktmpdir("regenerate-report-") do |root|
      run_dir = File.join(root, "2024-06-01__2024-07-01")
      FileUtils.cp_r(FIXTURE, run_dir)
      FileUtils.rm_f(File.join(run_dir, "snapshot.json"))
      metadata_path = File.join(run_dir, "metadata.json")
      metadata = JSON.parse(File.read(metadata_path))
      metadata["output_schema_version"] = "4.0.0"
      File.write(metadata_path, JSON.pretty_generate(metadata) + "\n")
      # The reviewed baseline normalizes timestamps to an HTML placeholder.
      %w[summary.json report.html].each do |name|
        path = File.join(run_dir, name)
        File.write(path, File.read(path).gsub("<generated_at>", "2024-07-01T12:00:00Z"))
      end
      yield run_dir
    end
  end

  def snapshot_files(run_dir)
    Dir.children(run_dir).sort.to_h { |name| [name, File.binread(File.join(run_dir, name))] }
  end

  def regenerate(run_dir)
    Open3.capture2e(RbConfig.ruby, SCRIPT, run_dir)
  end

  def test_regeneration_restores_the_complete_report_and_changes_no_other_files
    with_snapshot do |run_dir|
      expected = snapshot_files(run_dir)
      File.write(File.join(run_dir, "report.html"), "Incomplete report")

      2.times do
        output, status = regenerate(run_dir)
        assert status.success?, output
        assert_equal expected, snapshot_files(run_dir)
      end
    end
  end

  def test_missing_malformed_or_invalid_metrics_leave_the_snapshot_unchanged
    mutations = {
      "missing file" => ->(path) { FileUtils.rm(path) },
      "malformed JSON" => ->(path) { File.write(path, "{") },
      "unsupported version" => ->(data) { data["metric_version"] = "99.0.0" },
      "invalid count" => ->(data) { data["rows"].first["rnal"] = -1 },
      "inconsistent accounting" => ->(data) { data["rows"].first["intersection"] += 1 },
      "different run" => ->(data) { data["run_id"] = "2024-05-01__2024-07-01" },
      "missing provenance" => ->(data) { data.delete("source_files") },
      "different source hash" => ->(data) { data["source_files"]["airbnb"]["sha256"] = "0" * 64 },
      "different methodology" => ->(data) { data["methodology_version"] = "2.0.0" },
      "different source date" => ->(data) { data["source_dates"]["official_register_date"] = "2020-01-02" },
      "different announcement total" => ->(data) do
        data["rows"].first["announcements"] += 1
        data["rows"].first["empty_licence"] += 1
      end,
      "different official entry total" => ->(data) { data["rows"].first["official_entries"] += 1 }
    }
    mutations.each do |name, mutate|
      with_snapshot do |run_dir|
        path = File.join(run_dir, "registration_metrics.json")
        if ["missing file", "malformed JSON"].include?(name)
          mutate.call(path)
        else
          data = JSON.parse(File.read(path))
          mutate.call(data)
          File.write(path, JSON.generate(data))
        end
        before = snapshot_files(run_dir)
        output, status = regenerate(run_dir)
        refute status.success?, name
        assert_includes output, "Cannot regenerate report", name
        assert_equal before, snapshot_files(run_dir), name
      end
    end
  end

  def test_summary_provenance_must_match_the_snapshot
    %w[run_id methodology_version source_dates].each do |key|
      with_snapshot do |run_dir|
        path = File.join(run_dir, "summary.json")
        summary = JSON.parse(File.read(path))
        summary[key] = nil
        File.write(path, JSON.generate(summary))
        before = snapshot_files(run_dir)

        output, status = regenerate(run_dir)
        refute status.success?
        assert_includes output, "Summary provenance differs: #{key}"
        assert_equal before, snapshot_files(run_dir)
      end
    end
  end
end
