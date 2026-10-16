require "minitest/autorun"
require_relative "../lib/alojamento_local"

class AlojamentoLocalTest < Minitest::Test
  def test_project_files_follow_zeitwerk_conventions
    AlojamentoLocal::LOADER.eager_load(force: true)
    assert true
  rescue Zeitwerk::NameError => error
    flunk error.message
  end

  def test_normalizes_leading_zeroes_and_whitespace_in_al_licenses
    assert_equal "1584", AlojamentoLocal.parse_al_license("001584/AL")
    assert_equal "104882", AlojamentoLocal.parse_al_license("104882\t/AL")
  end

  def test_normalizes_legacy_year_suffix
    assert_equal "22720", AlojamentoLocal.parse_al_license("22720/2018")
  end

  def test_trims_invisible_format_characters_and_unicode_whitespace_at_boundaries
    ["\u200B 35505/AL", "\uFEFF35505/AL", "35505/AL\u200B", "\u200E35505/AL\u200F",
      "\u00A035505/AL\u2028", "\u200B \uFEFF 0035505/AL \u200B"].each do |raw|
      original = raw.dup
      assert_equal "35505", AlojamentoLocal.parse_al_license(raw), raw.dump
      assert_equal original, raw, "The raw source value must remain unchanged"
    end
    assert_equal "71027", AlojamentoLocal.parse_al_license("71027/AL\u2028")
    assert_nil AlojamentoLocal.parse_al_license("\u200B\uFEFF\u00A0")
  end

  def test_invisible_characters_do_not_allow_ambiguous_or_other_registration_values
    ["35\u200B505/AL", "\u200B406/UT/2017", "\uFEFFExempt", "\u200B123/AL;456/AL"].each do |raw|
      assert_nil AlojamentoLocal.parse_al_license(raw), raw.dump
    end
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

  def test_accepts_a_single_well_formed_al_number_in_surrounding_text
    assert_equal "12807", AlojamentoLocal.parse_al_license("Registration Number: 12807/AL")
    assert_equal "123", AlojamentoLocal.parse_al_license("registration number: 00123 /AL")
    ["Registration Number: 406/UT/2017", "Registration Number: 123", "Registration Number: 123/AL and 456/AL"].each do |value|
      assert_nil AlojamentoLocal.parse_al_license(value)
    end
    {"Local Accomodation N.º 23405/AL" => "23405", "Text 123/AL" => "123", "123/AL text" => "123",
     "Registered: (00123 / al)." => "123", "\u200BText 123/AL" => "123", "123/AL text\u200B" => "123",
     "Registo n.º 36419/ AL" => "36419"}.each do |raw, number|
      original = raw.dup
      assert_equal number, AlojamentoLocal.parse_al_license(raw), raw.dump
      assert_equal original, raw
    end
    {"81551/AL" => "81551", "34367" => "34367", "AL15252" => "15252", "00123/AL" => "123"}.each do |raw, normalized|
      assert_equal normalized, AlojamentoLocal.parse_al_license(raw)
    end
  end

  def test_does_not_extract_partial_or_ambiguous_numbers_from_prose
    ["Text 123/AL;456/AL", "123/AL and AL456", "123/AL;456", "123;456/AL", "45.222/AL",
      "1041/POL/2014/AL", "Text x123/AL", "Text 123/ALgarve", "Text 123/AL/2017",
      "Text 35\u200B505/AL", "Licence 123/UT/2017", "Text 123/2018", "Text 123", "Text AL123"].each do |raw|
      assert_nil AlojamentoLocal.parse_al_license(raw), raw.dump
    end
  end
end
