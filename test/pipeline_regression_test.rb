require "minitest/autorun"
require "minitest/mock"
require_relative "support/pipeline_fixture"

class PipelineRegressionTest < Minitest::Test
  def test_source_to_snapshot_regression_and_independent_accounting
    PipelineFixture.with_sources do |root, airbnb, official|
      result = PipelineFixture.run(root, airbnb, official)
      document = AlojamentoLocal::CandidateDataset.new(result[:path]).document
      expected = JSON.parse(File.read(File.join(PipelineFixture::EXPECTED, "public", "snapshot.json")))
      assert_equal expected, document
      assert_equal({listings: 11, candidates: 11, distinct_al_numbers: 4, rnal: 3}, result[:summary])
      assert_equal (1..11).map(&:to_s).sort, document["candidates"].flat_map { |c| c["listing_ids"] }.uniq.sort
      assert_equal 12, document["candidates"].sum { |c| c["listing_count"] }
      assert_equal 2, document["candidates"].count { |c| c["listing_ids"].include?("4") }
      assert_equal 2, document["candidates"].count { |c| c["registration_status"] == "exempt" }
      assert_equal 4, document["rnal"]["parishes"].sum { |r| r["count"] }, "Distinct parish sets are nonadditive"
      assert_equal 11, document["listings"]["parishes"].sum { |r| r["count"] }
      assert_equal 1, document["listings"]["parishes"].find { |r| r["freguesia"].nil? }["count"]
      assert_equal %i[path run_id summary], result.keys.sort
      assert_equal ["snapshot.json"], Dir.children(result[:path])
      refute Dir.exist?(File.join(root, "private"))
      before = File.binread(File.join(result[:path], "snapshot.json"))
      assert_equal result[:summary], PipelineFixture.run(root, airbnb, official)[:summary]
      assert_equal before, File.binread(File.join(result[:path], "snapshot.json"))
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
      document = AlojamentoLocal::Analysis::Result.new(sources: pair).snapshot
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
      json = File.join(previous[:path], "snapshot.json")
      before = File.binread(json)
      sources = PipelineFixture.pair(airbnb, official)
      result = AlojamentoLocal::Analysis::Result.new(sources: sources)
      publisher = AlojamentoLocal::Analysis::ResultPublisher.new(destination: previous[:path])
      sources.stub(:verify_unchanged!, -> { raise Interrupt, "changed/interrupted" }) do
        assert_raises(Interrupt) { publisher.publish(result: result, sources: sources) }
      end
      assert_equal before, File.binread(json)
      assert_equal ["snapshot.json"], Dir.children(previous[:path])
      result.snapshot["candidates"].first["listing_count"] = 99
      assert_raises(ArgumentError) { publisher.publish(result: result, sources: sources) }
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
      File.write(File.join(other, "snapshot.json"), "other pair")
      json = File.join(previous[:path], "snapshot.json")
      before = File.binread(json)
      sources = PipelineFixture.pair(airbnb, official)
      result = AlojamentoLocal::Analysis::Result.new(sources: sources)
      publisher = AlojamentoLocal::Analysis::ResultPublisher.new(destination: previous[:path])
      real_rename = File.method(:rename)
      rename = ->(from, to) do
        raise IOError, "final rename failed" if to == json
        real_rename.call(from, to)
      end
      File.stub(:rename, rename) do
        assert_raises(IOError) { publisher.publish(result: result, sources: sources) }
      end
      assert_equal before, File.binread(json)
      assert_equal "other pair", File.read(File.join(other, "snapshot.json"))
    end
  end

  def test_listing_order_does_not_change_groups_ids_or_medoid
    PipelineFixture.with_sources do |_, airbnb, official|
      first = AlojamentoLocal::Analysis::Result.new(sources: PipelineFixture.pair(airbnb, official)).snapshot
      table = CSV.read(airbnb, headers: true)
      CSV.open(airbnb, "w") { |csv|
        csv << table.headers
        table.reverse_each { |row| csv << row.fields }
      }
      File.delete("#{airbnb}.manifest.json")
      second = AlojamentoLocal::Analysis::Result.new(sources: PipelineFixture.pair(airbnb, official)).snapshot
      assert_equal first, second
      merged = first["candidates"].find { |c| c["listing_ids"] == %w[1 2] }
      assert_equal 0, merged["official_match"]["distance_km"], "Two-member medoid ties select ID 1"
      assert_equal "Arroios", merged["freguesia"]
      assert_equal "Arroios", merged["geography"]["coordinate_freguesia"]
    end
  end
end
