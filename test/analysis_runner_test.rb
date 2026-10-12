require "minitest/autorun"
require "minitest/mock"
require_relative "../lib/alojamento_local/analysis_runner"

class AnalysisRunnerTest < Minitest::Test
  def test_invalid_options_fail_before_preparing_sources
    AlojamentoLocal::Data.stub(:prepare!, -> { flunk "Invalid options must not download sources" }) do
      [{mode: "unknown"}, {mode: "public", force: true}, {reuse_existing: true}].each do |options|
        assert_raises(ArgumentError) { AlojamentoLocal::AnalysisRunner.run(**options) }
      end
    end
  end

  def test_current_public_run_skips_analysis
    existing = {run_id: "2024-06-01__2024-07-01", path: "data/snapshots/existing"}
    AlojamentoLocal::Data.stub(:prepare!, %w[airbnb.csv official.csv]) do
      AlojamentoLocal::Analysis.stub(:existing_public_run, existing) do
        AlojamentoLocal::Analysis.stub(:run, ->(**) { flunk "A current run must not be rewritten" }) do
          assert_equal existing.merge(reused: true), AlojamentoLocal::AnalysisRunner.run(mode: "public", reuse_existing: true)
        end
      end
    end
  end

  def test_outdated_public_run_is_reanalysed
    result = {run_id: "new", path: "output", summary: {}}
    analyse = ->(**options) do
      assert_equal({airbnb_path: "airbnb.csv", official_path: "official.csv",
                    mode: "public", force: false, generate_pdf: true}, options)
      result
    end
    AlojamentoLocal::Data.stub(:prepare!, %w[airbnb.csv official.csv]) do
      AlojamentoLocal::Analysis.stub(:existing_public_run, nil) do
        AlojamentoLocal::Analysis.stub(:run, analyse) do
          assert_equal result.merge(reused: false), AlojamentoLocal::AnalysisRunner.run(mode: "public", reuse_existing: true, generate_pdf: true)
        end
      end
    end
  end

  def test_local_rerun_does_not_check_public_outputs
    analyse = ->(**options) do
      assert_equal "local", options.fetch(:mode)
      assert options.fetch(:force)
      {run_id: "rerun", path: "private", summary: {}}
    end
    AlojamentoLocal::Data.stub(:prepare!, %w[airbnb.csv official.csv]) do
      AlojamentoLocal::Analysis.stub(:existing_public_run, ->(**) { flunk "Local runs must not reuse public outputs" }) do
        AlojamentoLocal::Analysis.stub(:run, analyse) do
          refute AlojamentoLocal::AnalysisRunner.run(force: true).fetch(:reused)
        end
      end
    end
  end

  def test_changed_source_hash_error_is_not_treated_as_a_missing_run
    AlojamentoLocal::Data.stub(:prepare!, %w[airbnb.csv official.csv]) do
      AlojamentoLocal::Analysis.stub(:existing_public_run, ->(**) { raise "Source hashes differ" }) do
        AlojamentoLocal::Analysis.stub(:run, ->(**) { flunk "Changed sources must not replace an existing run" }) do
          error = assert_raises(RuntimeError) { AlojamentoLocal::AnalysisRunner.run(mode: "public", reuse_existing: true) }
          assert_equal "Source hashes differ", error.message
        end
      end
    end
  end
end
