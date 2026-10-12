require "minitest/autorun"
require_relative "../lib/alojamento_local"

class AlojamentoLocalTest < Minitest::Test
  def test_normalizes_leading_zeroes_and_whitespace_in_al_licenses
    assert_equal "1584", AlojamentoLocal.parse_al_license("001584/AL")
    assert_equal "104882", AlojamentoLocal.parse_al_license("104882\t/AL")
  end

  def test_normalizes_legacy_year_suffix
    assert_equal "22720", AlojamentoLocal.parse_al_license("22720/2018")
  end

  def test_does_not_treat_tourist_undertaking_number_as_al_license
    assert_nil AlojamentoLocal.parse_al_license("406/UT/2017")
  end

  def test_distinguishes_empty_license_fields_from_unrecognised_formats
    assert_equal "sem licença", AlojamentoLocal.missing_license_assessment(nil)
    assert_equal "sem licença", AlojamentoLocal.missing_license_assessment("  ")
    assert_equal "sem licença identificável", AlojamentoLocal.missing_license_assessment("406/UT/2017")
    assert_equal "sem licença identificável", AlojamentoLocal.missing_license_assessment("Exempt")
    assert_equal "sem licença", AlojamentoLocal.license_group_assessment([{licensa: nil, licensa_raw: nil}], nil)
    assert_equal "sem licença identificável", AlojamentoLocal.license_group_assessment([{licensa: nil, licensa_raw: "406/UT/2017"}], nil)
  end

  def test_parses_coordinates_with_spaces_around_separator
    assert_equal [38.7530581, -9.181339], AlojamentoLocal.parse_lat_long("38.7530581 ; -9.181339")
  end

  def test_parses_coordinates_without_spaces_and_with_decimal_commas
    assert_equal [38.7530581, -9.181339], AlojamentoLocal.parse_lat_long("38,7530581;-9,181339")
  end

  def test_local_is_the_default_cli_mode
    assert_equal "local", AlojamentoLocal::CLI.mode!([])
    assert_equal "public", AlojamentoLocal::CLI.mode!(["--mode", "public"])
  end

  def test_cli_accepts_local_mode_without_adding_a_public_details_option
    assert_equal "local", AlojamentoLocal::CLI.mode!(["--mode=local"])
    assert_raises(ArgumentError) { AlojamentoLocal::CLI.mode!(["--include-details"]) }
  end

  def test_accepts_only_the_explicit_single_al_registration_prefix
    assert_equal "12807", AlojamentoLocal.parse_al_license("Registration Number: 12807/AL")
    assert_equal "123", AlojamentoLocal.parse_al_license("registration number: 00123 /AL")
    ["Registration Number: 406/UT/2017", "Registration Number: 123", "Registration Number: 123/AL and 456/AL", "Text 123/AL", "123/AL text"].each do |value|
      assert_nil AlojamentoLocal.parse_al_license(value)
    end
    {"81551/AL" => "81551", "34367" => "34367", "AL15252" => "15252", "00123/AL" => "123"}.each do |raw, normalized|
      assert_equal normalized, AlojamentoLocal.parse_al_license(raw)
    end
  end
end
