require "minitest/autorun"
require "minitest/mock"
require_relative "support/pipeline_fixture"
require_relative "support/candidate_fixture"

class PipelineRegressionTest < Minitest::Test
  def test_source_to_snapshot_regression_and_independent_accounting
    PipelineFixture.with_sources do |root, airbnb, official|
      result = PipelineFixture.run(root, airbnb, official)
      loaded = AlojamentoLocal::CandidateDataset.new(result[:path])
      built = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: PipelineFixture.pair(airbnb, official)).build
      assert_instance_of AlojamentoLocal::CandidateDataset, built
      assert_equal loaded.summary_document, built.summary_document
      assert_equal loaded.details_document, built.details_document
      assert_equal result[:summary], loaded.summary
      assert_equal loaded.summary, built.summary
      document = CandidateFixture.documents(loaded)
      expected = CandidateFixture.documents(AlojamentoLocal::CandidateDataset.new(File.join(PipelineFixture::EXPECTED, "public")))
      assert_equal expected, document
      assert_equal({listings: 11, candidates: 11, distinct_al_numbers: 4, rnal: 3}, result[:summary])
      assert_equal (1..11).map(&:to_s).sort, document["candidates"].flat_map { |c| c["listing_ids"] }.uniq.sort
      assert_equal 12, document["candidates"].sum { |c| c["listing_count"] }
      assert_equal 2, document["candidates"].count { |c| c["listing_ids"].include?("4") }
      assert_equal 2, document["candidates"].count { |c| c["registration_status"] == "exempt" }
      assert_equal 4, document["parishes"].sum { |r| r["official_count"] }, "Distinct parish sets are nonadditive"
      assert_equal 11, document["parishes"].sum { |r| r["listings_count"] }
      assert_equal 1, document["parishes"].find { |r| r["freguesia"].nil? }["listings_count"]
      assert_equal %i[path run_id summary], result.keys.sort
      assert_equal AlojamentoLocal::CandidateDataset::FILES.sort, Dir.children(result[:path]).sort
      refute Dir.exist?(File.join(root, "private"))
      before = AlojamentoLocal::CandidateDataset::FILES.map { |file| File.binread(File.join(result[:path], file)) }
      assert_equal result[:summary], PipelineFixture.run(root, airbnb, official)[:summary]
      assert_equal before, AlojamentoLocal::CandidateDataset::FILES.map { |file| File.binread(File.join(result[:path], file)) }
    end
  end

  def test_cross_declaration_groups_preserve_raw_values_source_totals_and_signals
    PipelineFixture.with_sources do |_, airbnb, official|
      [true, false].each do |numbered|
        template = CSV.read(File.join(PipelineFixture::SOURCES, "listings-2024-06-01.csv"), headers: true)
        rows = template.take(5).map(&:to_h)
        licences = numbered ? ["100/AL", nil, "Exempt", "UT registration", ""] : [nil, "", "Exempt", "UT registration", "Isento"]
        rows.each_with_index do |row, index|
          row.merge!("license" => licences[index], "latitude" => "38.73", "longitude" => "-9.14",
            "name" => "Central lovely apartment B room", "description" => (1..40).map { |i| "token#{i}" }.join(" "),
            "room_type" => "Private room", "host_id" => index.to_s)
        end
        # An inferred association must not create a new source declaration in Belém.
        rows.last["neighbourhood_cleansed"] = "Belém"
        CSV.open(airbnb, "w") do |csv|
          csv << template.headers
          rows.each { |row| csv << template.headers.map { |key| row[key] } }
        end
        File.delete("#{airbnb}.manifest.json") if File.exist?("#{airbnb}.manifest.json")
        dataset = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: PipelineFixture.pair(airbnb, official)).build
        assert_equal 1, dataset.candidates.size
        candidate = dataset.candidates.first
        assert_equal licences, rows.map { |row| candidate["raw_licences"][row["id"]] }
        assert_equal numbered ? "100" : nil, candidate["al_number"]
        assert_equal numbered ? "found" : "mixed", candidate["registration_status"]
        assert_nil candidate["freguesia"]
        assert_equal 5, dataset.summary[:listings]
        assert_equal 3, dataset.summary[:rnal]
        assert_equal 10, dataset.grouping_assessments.size
        assert_equal numbered ? 1 : 0, dataset.summary_document.dig("lisbon", "matched_al_numbers_count")
        assert_equal numbered ? 0 : 1, dataset.summary_document.dig("lisbon", "mixed_licence_candidates_count")
        assert_equal 0, dataset.summary_document["parishes"].last["matched_al_numbers_count"]
        assert_equal [2, 1, 3], dataset.summary_document["signals"].values_at("empty_licence_listings", "unrecognised_licence_listings", "unidentified_licence_listings")
        site = AlojamentoLocal::SiteData.new(dataset: dataset).site_data
        assert_equal 1, site["metrics"]["candidate_breakdown"].sum { |segment| segment["count"] }
        assert_equal 1, site["report_candidates"].size
        invalid = CandidateFixture.documents(dataset)
        invalid["candidates"].first["raw_licences"][rows.last["id"]] = "999/AL"
        assert_raises(ArgumentError) { CandidateFixture.from_documents(invalid, refresh: true) }
      end
    end
  end

  def test_registered_apartment_separation_is_published_validated_and_clears_review_signals
    PipelineFixture.with_sources do |root, airbnb, official|
      table = CSV.read(airbnb, headers: true)
      CSV.open(airbnb, "w") do |csv|
        csv << table.headers
        table.take(2).each_with_index do |row, index|
          values = row.to_h.merge("license" => "#{100 + index * 100}/AL", "room_type" => "Entire home/apt",
            "property_type" => "Entire rental unit", "latitude" => "38.73", "longitude" => "-9.14",
            "name" => "Central studio balcony #{index + 1} floor", "description" => (1..40).map { |i| "token#{i}" }.join(" "))
          csv << table.headers.map { |key| values[key] }
        end
      end
      CSV.open(official, "w") do |csv|
        csv << %w[NrRNAL Concelho Freguesia LatLong Modalidade NUTSII]
        [100, 200].each { |number| csv << [number, "Lisboa", "Arroios", "38.73;-9.14", "Apartamento", "Grande Lisboa"] }
      end
      result = PipelineFixture.run(root, airbnb, official)
      dataset = AlojamentoLocal::CandidateDataset.new(result.fetch(:path))
      pair = dataset.grouping_assessments.fetch(0)
      assert_equal [7, "separate", "separate_apartments"], pair.values_at("score", "outcome", "relationship")
      assert_equal 2, dataset.candidates.size
      assert dataset.candidates.none? { |candidate| candidate["signals"].include?("grouping_review") }
      assert_equal 2, dataset.summary_document.dig("lisbon", "matched_al_numbers_count")
      [
        ->(doc) { doc["grouping_assessments"].first["outcome"] = "review" },
        ->(doc) { doc["grouping_assessments"].first["relationship"] = "undetermined" },
        ->(doc) { doc["grouping_assessments"].first["reasons"].delete("distinct_registered_apartments") },
        ->(doc) { doc["candidates"].first["official_match"]["type"] = nil },
        ->(doc) { doc["candidates"].first["official_match"]["municipality"] = "Porto" },
        ->(doc) {
          doc["grouping_assessments"].first["reasons"] << "same_apartment_reference"
          doc["grouping_assessments"].first["score"] += 3
        }
      ].each do |mutate|
        doc = CandidateFixture.documents(dataset)
        mutate.call(doc)
        assert_raises(ArgumentError) { CandidateFixture.from_documents(doc, refresh: true) }
      end
    end
  end

  def test_attribute_separation_is_published_validated_and_clears_review_signals
    PipelineFixture.with_sources do |root, airbnb, official|
      table = CSV.read(airbnb, headers: true)
      headers = (table.headers + %w[beds accommodates]).uniq
      CSV.open(airbnb, "w") do |csv|
        csv << headers
        table.take(2).each_with_index do |row, index|
          values = row.to_h.merge("license" => "100/AL", "room_type" => "Entire home/apt",
            "bedrooms" => index.to_s, "beds" => (index + 2).to_s, "accommodates" => (index * 2 + 2).to_s)
          csv << headers.map { |key| values[key] }
        end
      end
      result = PipelineFixture.run(root, airbnb, official)
      dataset = AlojamentoLocal::CandidateDataset.new(result.fetch(:path))
      assessment = dataset.grouping_assessments.fetch(0)
      assert_equal ["separate", "separate_apartments"], assessment.values_at("outcome", "relationship")
      assert_includes assessment["reasons"], "distinct_apartment_attributes"
      assert_equal 2, dataset.candidates.size
      assert dataset.candidates.all? { |candidate| candidate["signals"].include?("shared_number") }
      assert dataset.candidates.none? { |candidate| candidate["signals"].include?("grouping_review") }
      [
        ->(pair) { pair["outcome"] = "review" },
        ->(pair) { pair["relationship"] = "undetermined" },
        ->(pair) { pair["reasons"].delete("different_apartment_bedrooms") },
        ->(pair) {
          pair["reasons"] << "same_apartment_reference"
          pair["score"] += 3
        }
      ].each do |mutate|
        doc = CandidateFixture.documents(dataset)
        mutate.call(doc["grouping_assessments"].first)
        assert_raises(ArgumentError) { CandidateFixture.from_documents(doc, refresh: true) }
      end
    end
  end

  def test_containing_flat_merge_round_trips_with_complete_link_and_source_accounting
    PipelineFixture.with_sources do |root, airbnb, official|
      table = CSV.read(airbnb, headers: true)
      description = "The suite is in a 180m² flat with 3 other suites. #{(1..40).map { |i| "word#{i}" }.join(" ")}"
      rows = table.take(3).map.with_index do |row, index|
        row.to_h.merge("license" => "100/AL", "host_id" => "7", "room_type" => "Private room",
          "name" => ["Quiet single suite", "Bright double suite", "Sunny spacious room"][index],
          "latitude" => "38.73", "longitude" => "-9.14",
          "description" => case index
                           when 1 then "#{description} #{(1..15).map { |i| "extra#{i}" }.join(" ")}"
                           when 2 then description.sub("180m²", "190m²")
                           else description
                           end)
      end
      write_rows = ->(values) {
        CSV.open(airbnb, "w") do |csv|
          csv << table.headers
          values.each { |row| csv << table.headers.map { |key| row[key] } }
        end
      }
      write_rows.call(rows)
      result = PipelineFixture.run(root, airbnb, official)
      dataset = AlojamentoLocal::CandidateDataset.new(result.fetch(:path))
      assert_equal [%w[1 2], %w[3]], dataset.candidates.map { |candidate| candidate["listing_ids"] }.sort
      assessment = dataset.grouping_assessments.find { |pair| pair["listing_ids"] == %w[1 2] }
      assert_equal [8, "merge", "separate_rooms"], assessment.values_at("score", "outcome", "relationship")
      assert_equal 3, dataset.summary[:listings]
      assert_equal 2, dataset.summary[:candidates]
      assert_equal 1, dataset.summary_document.dig("lisbon", "matched_al_numbers_count")
      assert_equal({"1" => "100/AL", "2" => "100/AL", "3" => "100/AL"}, dataset.candidates.map { |c| c["raw_licences"] }.reduce(&:merge))
      ["same_host", "same_al_number", "same_containing_apartment"].each do |reason|
        doc = CandidateFixture.documents(dataset)
        pair = doc["grouping_assessments"].find { |item| item["listing_ids"] == %w[1 2] }
        pair["reasons"].delete(reason)
        pair["score"] -= AlojamentoLocal::Analysis::Grouping::POINTS.fetch(reason)
        assert_raises(ArgumentError) { CandidateFixture.from_documents(doc, refresh: true) }
      end
      original = AlojamentoLocal::CandidateDataset::FILES.map { |file| File.binread(File.join(result[:path], file)) }
      write_rows.call(rows.reverse)
      File.delete("#{airbnb}.manifest.json")
      PipelineFixture.run(root, airbnb, official)
      assert_equal original, AlojamentoLocal::CandidateDataset::FILES.map { |file| File.binread(File.join(result[:path], file)) }
      # All evidence can coexist; the contract must accept the full 16-point score.
      rows.take(2).each { |row| row.merge!("name" => "Central lovely apartment B room 1", "description" => description) }
      write_rows.call(rows.take(2))
      File.delete("#{airbnb}.manifest.json")
      PipelineFixture.run(root, airbnb, official)
      maximum = AlojamentoLocal::CandidateDataset.new(result.fetch(:path))
      assert_equal [16, "merge", "duplicate_adverts"], maximum.grouping_assessments.first.values_at("score", "outcome", "relationship")
    end
  end

  def test_national_record_consensus_and_independent_lisbon_summary
    PipelineFixture.with_sources do |_, airbnb, official|
      pair = PipelineFixture.pair(airbnb, official)
      records = pair.official.records
      assert_equal 6, pair.official.entries.size
      assert_equal "Lisboa", records["100"]["municipality"]
      assert_nil records["100"]["freguesia"]
      assert_equal [38.73, -9.14], records["100"]["coordinates"]
      %w[municipality freguesia coordinates district].each { |key| assert_nil records["200"][key] }
      assert_nil records["300"]["coordinates"]
      assert_equal "Faro", records["400"]["municipality"]
      document = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: pair).build.then { |dataset| CandidateFixture.documents(dataset) }
      conflict = document["candidates"].find { |c| c["al_number"] == "200" }
      assert_equal "found", conflict["registration_status"]
      assert_nil conflict["official_match"]["distance_km"]
      # Reverse source rows: no first-row selection or nearest-location selection.
      table = CSV.read(official, headers: true)
      CSV.open(official, "w") { |csv|
        csv << table.headers
        table.reverse_each { |row| csv << row.fields }
      }
      assert_equal records, AlojamentoLocal::Analysis::DataSource::Official.new(official).records
    end
  end

  def test_overlap_uses_distinct_numbers_and_lisbon_source_rows_before_national_resolution
    PipelineFixture.with_sources do |_, airbnb, official|
      dataset = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: PipelineFixture.pair(airbnb, official)).build
      site = AlojamentoLocal::SiteData.new(dataset: dataset).site_data
      assert_equal [3, 11, 3, 0, 1], site["metrics"].values_at("rnal", "airbnb", "matched_al_numbers", "unmatched_official_numbers", "other_declared_numbers")
      assert_equal [11, 4], site["metrics"].values_at("candidate_count", "unnumbered_candidates")
      arroios = site["districts"].find { |row| row["name"] == "Arroios" }
      belem = site["districts"].find { |row| row["name"] == "Belém" }
      assert_equal [2, 10, 2, 0, 1], arroios["metrics"].values_at("rnal", "airbnb", "matched_al_numbers", "unmatched_official_numbers", "other_declared_numbers")
      assert_equal [2, 0, 0, 2, 0], belem["metrics"].values_at("rnal", "airbnb", "matched_al_numbers", "unmatched_official_numbers", "other_declared_numbers")
      assert_equal [0, 1, 0], site["unknown"]["metrics"].values_at("rnal", "airbnb", "matched_al_numbers")
      # 100's official parish is contradictory and 200's municipality is contradictory.
      # Their explicit Lisbon source rows still put both numbers in the city set.
      assert_nil dataset.candidates.find { |row| row["al_number"] == "100" }.dig("official_match", "freguesia")
      assert_nil dataset.candidates.find { |row| row["al_number"] == "200" }.dig("official_match", "municipality")
      assert_equal 3, dataset.summary_document.dig("lisbon", "matched_al_numbers_count")
      assert_operator dataset.candidates.count { |row| row["al_number"] }, :>, site["metrics"]["declared_numbers"]
    end
  end

  def test_missing_columns_and_duplicate_or_nonnumeric_ids_fail_locally
    PipelineFixture.with_sources do |_, airbnb, _|
      original = File.read(airbnb)
      File.write(airbnb, original + original.lines[1])
      error = assert_raises(ArgumentError) { AlojamentoLocal::Analysis::DataSource::Airbnb.new(airbnb) }
      assert_includes error.message, "duplicate listing IDs"
      assert_includes error.message, 'duplicates=["1"]'
      refute File.exist?("#{airbnb}.invalid-ids.json")
      File.write(airbnb, original.sub(/^1,/, "bad,"))
      assert_raises(ArgumentError) { AlojamentoLocal::Analysis::DataSource::Airbnb.new(airbnb) }
      File.write(airbnb, "id,license\n1,100/AL\n")
      assert_raises(ArgumentError) { AlojamentoLocal::Analysis::DataSource::Airbnb.new(airbnb) }
    end
  end

  def test_source_change_interruption_or_invalid_output_preserves_previous_snapshot
    PipelineFixture.with_sources do |root, airbnb, official|
      previous = PipelineFixture.run(root, airbnb, official)
      json = File.join(previous[:path], "summary.json")
      before = File.binread(json)
      sources = PipelineFixture.pair(airbnb, official)
      dataset = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: sources).build
      publisher = AlojamentoLocal::Analysis::ResultPublisher.new(destination: previous[:path])
      sources.stub(:verify_unchanged!, -> { raise Interrupt, "changed/interrupted" }) do
        assert_raises(Interrupt) { publisher.publish(dataset: dataset, sources: sources) }
      end
      assert_equal before, File.binread(json)
      assert_equal AlojamentoLocal::CandidateDataset::FILES.sort, Dir.children(previous[:path]).sort
      dataset.candidates.first["listing_count"] = 99
      assert_raises(ArgumentError) { publisher.publish(dataset: dataset, sources: sources) }
      assert_equal before, File.binread(json)
      File.open(airbnb, "a") { |file| file.write("\n") }
      assert_raises(RuntimeError) { sources.verify_unchanged! }
      assert_raises(RuntimeError) { PipelineFixture.run(root, airbnb, official) }
      assert_equal before, File.binread(json)
    end
  end

  def test_final_rename_failure_preserves_snapshot_and_other_pairs
    PipelineFixture.with_sources do |root, airbnb, official|
      previous = PipelineFixture.run(root, airbnb, official)
      other = File.join(root, "public", "2024-01-01__2024-02-01")
      FileUtils.mkdir_p(other)
      File.write(File.join(other, "summary.json"), "other pair")
      json = File.join(previous[:path], "summary.json")
      before = File.binread(json)
      sources = PipelineFixture.pair(airbnb, official)
      dataset = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: sources).build
      publisher = AlojamentoLocal::Analysis::ResultPublisher.new(destination: previous[:path])
      real_rename = File.method(:rename)
      rename = ->(from, to) do
        raise IOError, "final rename failed" if to == previous[:path] && from.include?(".candidate-")
        real_rename.call(from, to)
      end
      File.stub(:rename, rename) do
        assert_raises(IOError) { publisher.publish(dataset: dataset, sources: sources) }
      end
      assert_equal before, File.binread(json)
      assert_equal "other pair", File.read(File.join(other, "summary.json"))
    end
  end

  def test_listing_order_does_not_change_groups_ids_or_medoid
    PipelineFixture.with_sources do |_, airbnb, official|
      first = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: PipelineFixture.pair(airbnb, official)).build.then { |dataset| CandidateFixture.documents(dataset) }
      table = CSV.read(airbnb, headers: true)
      CSV.open(airbnb, "w") { |csv|
        csv << table.headers
        table.reverse_each { |row| csv << row.fields }
      }
      File.delete("#{airbnb}.manifest.json")
      second = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: PipelineFixture.pair(airbnb, official)).build.then { |dataset| CandidateFixture.documents(dataset) }
      assert_equal first, second
      merged = first["candidates"].find { |c| c["listing_ids"] == %w[1 2] }
      assert_equal 0, merged["official_match"]["distance_km"], "Two-member medoid ties select ID 1"
      assert_equal "Arroios", merged["freguesia"]
      assert_equal "Arroios", merged["geography"]["coordinate_freguesia"]
    end
  end
end
