require "minitest/autorun"
require_relative "../lib/alojamento_local"

class DeclarationTest < Minitest::Test
  def parse(raw) = AlojamentoLocal::Analysis::Declaration.new(raw)

  def test_supported_single_values_and_boundary_normalization
    {"001584/AL" => "1584", "104882\t/AL" => "104882", "22720/2018" => "22720",
     "AL15252" => "15252", "\u200B \uFEFF 0035505/AL \u200B" => "35505", "00123" => "123"}.each do |raw, number|
      assert_equal [number], parse(raw).numbers
      assert_equal raw, parse(raw).raw
      refute parse(raw).partial?
    end
  end

  def test_multi_numbers_deduplication_partial_extraction_and_original_value
    raw = "Registo: 00123/AL; 456 / AL; AL123 + 789/UT/2017"
    result = parse(raw)
    assert_equal %w[123 456], result.numbers
    assert_equal raw, result.raw
    assert result.partial?
    assert_includes result.residual, "789/UT/2017"
    assert_equal %w[123 456], parse("123/AL;456/AL").numbers
    refute parse("123/AL;456/AL").partial?
    assert_equal %w[123 456], parse("123/AL and AL456").numbers
    assert_equal ["123"], parse("123/AL; unsupported 456").numbers
    assert parse("123/AL text").partial?
  end

  def test_exemptions_never_become_numbers_or_incidental_prose_matches
    ["Exempt", "exempt", "\u200BExempt\u00a0", "Isento", "Isenta de registo"].each do |raw|
      assert_empty parse(raw).numbers
      assert_equal "exempt", parse(raw).status
    end
    ["possibly Exempt", "Exempt number 123", "not Exempt", "exemption pending"].each do |raw|
      assert_equal "unrecognised", parse(raw).status
    end
    assert_equal "absent", parse(nil).status
    assert_equal "absent", parse(" \u200B ").status
  end

  def test_rejects_partial_tokens_other_schemes_and_thousands_fragments
    ["406/UT/2017", "45.222/AL", "45,222/AL", "45 222/AL", "AL45.222", "AL45,222/AL", "1041/POL/2014/AL",
      "x123/AL", "123/ALgarve", "123/AL/2017", "35\u200B505/AL", "Text 123/2018", "Text 123", "0/AL"].each do |raw|
      assert_empty parse(raw).numbers, raw.dump
    end
  end
end
