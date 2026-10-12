require "minitest/autorun"
require "open3"
require_relative "support/pipeline_fixture"

class PipelineRegressionTest < Minitest::Test
  def with_outputs
    Dir.mktmpdir("pipeline-regression-") do |root|
      yield PipelineFixture.outputs(root), root
    end
  end

  def test_complete_pipeline_matches_reviewed_expected_files
    with_outputs do |actual, _root|
      expected = {}
      Dir.glob(File.join(PipelineFixture::EXPECTED, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.each do |path|
        relative = path.delete_prefix(PipelineFixture::EXPECTED + "/")
        expected[relative] = File.read(path)
      end
      assert_equal 14, expected.size, "The baseline must contain public, local, history and site outputs"
      assert_equal expected.keys.sort, actual.keys.sort, "Output files added or removed"
      expected.each do |path, content|
        assert_equal content, actual.fetch(path), "Pipeline output changed: #{path}"
      end
    end
  end

  def test_fixture_totals_match_independent_accounting
    with_outputs do |files, _root|
      document = JSON.parse(files.fetch("public/snapshot.json"))
      metrics = document.fetch("registration_metrics")
      # Hand-counted from the synthetic sources, not from the calculator.
      fields = %w[rnal airbnb intersection rnal_only airbnb_only another_lisbon_parish another_municipality no_national_match unresolved_official_geography announcements empty_licence unrecognised_licence identifiable_number confirmed_rnal_match official_entries]
      expected = {
        "Lisboa" => [15, 18, 13, 2, 5, 0, 2, 1, 2, 34, 2, 2, 30, 28, 19],
        "Arroios" => [12, 15, 8, 4, 7, 1, 2, 1, 3, 30, 2, 2, 26, 24, 14],
        "Belém" => [2, 2, 0, 2, 2, 1, 0, 0, 1, 2, 0, 0, 2, 2, 2],
        "Ajuda" => [1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1],
        "Geografia não identificada" => [1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 2]
      }
      assert_equal 26, metrics.fetch("rows").size
      metrics.fetch("rows").each do |row|
        assert_equal ["geography", *fields], row.keys
        assert_equal expected.fetch(row.fetch("geography"), Array.new(fields.size, 0)), row.values_at(*fields), row.fetch("geography")
      end
      assert_equal({"national_entries" => 25, "unparseable_official_numbers" => 1,
                    "duplicate_number_extra_entries" => 5, "official_entries_unresolved_municipality" => 3,
                    "lisbon_entries_unresolved_parish" => 2}, metrics.fetch("diagnostics"))
      summary = document.fetch("summary")
      assert_equal [34, 18, 19, 28], summary.values_at("listings", "licence_groups", "official_registers_lisbon", "establishment_estimate")
      comparisons = summary.fetch("historical_comparisons").to_h { |row| [row.fetch("run_id"), row] }
      assert_equal "incompatível — metodologia diferente", comparisons.fetch("2024-05-01__2024-06-01").fetch("status")
      assert_empty comparisons.fetch("2024-05-01__2024-06-01").fetch("metrics")
      assert_equal "comparável", comparisons.fetch("2024-05-02__2024-06-02").fetch("status")
      assert_equal({"provável estabelecimento com anúncios múltiplos" => 1,
                    "licença repetida na mesma localização" => 2,
                    "licença repetida em várias localizações" => 1,
                    "licença oficial fora de Lisboa" => 2,
                    "número sem correspondência no RNAL" => 1,
                    "geografia oficial não identificada" => 6,
                    "localização observada não identificada" => 1,
                    "licença única em Lisboa" => 4}, summary.fetch("classifications"))
      assert_equal({"airbnb_snapshot_date" => "2024-06-01", "official_register_date" => "2020-01-01",
                    "official_register_download_date" => "2024-07-01"}, summary.fetch("source_dates"))
    end
  end

  def test_synthetic_public_outputs_pass_publication_audit
    with_outputs do |_files, root|
      artifact = File.join(root, "artifact")
      FileUtils.cp_r(File.join(root, "public", PipelineFixture::RUN_ID), artifact)
      FileUtils.cp(File.expand_path("../NOTICE", __dir__), File.join(artifact, "NOTICE"))
      output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", artifact)
      assert status.success?, output

      document = File.join(artifact, "snapshot.json")
      data = JSON.parse(File.read(document))
      data.fetch("parish_totals").first["licensa_raw"] = "123/AL"
      File.write(document, JSON.pretty_generate(data))
      output, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", artifact)
      refute status.success?
      assert_includes output, "campo proibido em snapshot.json: licensa_raw"
    end
  end
end
