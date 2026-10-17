require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require_relative "support/candidate_fixture"
require_relative "support/pipeline_fixture"

class SplitDatasetTest < Minitest::Test
  def with_pair
    Dir.mktmpdir do |root|
      path = File.join(root, "candidate")
      CandidateFixture.dataset.write_files(path)
      yield root, path
    end
  end

  def bytes(path)
    AlojamentoLocal::CandidateDataset::FILES.map { |name| File.binread(File.join(path, name)) }
  end

  def test_reproducible_pair_and_compact_gzip_metadata
    with_pair do |root, path|
      loaded = AlojamentoLocal::CandidateDataset.new(path)
      output = File.join(root, "again")
      loaded.write_files(output)
      assert_equal bytes(path), bytes(output)
      assert_equal CandidateFixture.dataset.summary, loaded.summary
      assert_equal CandidateFixture.dataset.details_document, loaded.details_document
      Zlib::GzipReader.open(File.join(path, "candidates.json.gz")) do |gzip|
        assert_equal 0, gzip.mtime.to_i
        assert_nil gzip.orig_name
        assert_nil gzip.comment
        decoded = gzip.read
        assert_equal JSON.generate(loaded.details_document) + "\n", decoded
      end
    end
  end

  def test_missing_malformed_corrupt_truncated_and_trailing_files_fail
    [
      ->(path) { File.delete(File.join(path, "summary.json")) },
      ->(path) { File.delete(File.join(path, "candidates.json.gz")) },
      ->(path) { File.write(File.join(path, "summary.json"), "{") },
      ->(path) { File.binwrite(File.join(path, "candidates.json.gz"), "bad gzip") },
      ->(path) { file = File.join(path, "candidates.json.gz"); File.truncate(file, File.size(file) - 5) },
      ->(path) { File.binwrite(File.join(path, "candidates.json.gz"), AlojamentoLocal::CandidateDataset.compress({"invalid" => []})) },
      ->(path) { File.open(File.join(path, "candidates.json.gz"), "ab") { |io| io.write("trailing") } }
    ].each do |mutation|
      with_pair do |_, path|
        mutation.call(path)
        assert_raises(Errno::ENOENT, JSON::ParserError, Zlib::Error, ArgumentError) { AlojamentoLocal::CandidateDataset.new(path) }
      end
    end
  end

  def test_every_candidate_aggregate_is_checked_against_details
    mutations = [
      ->(s) { s["lisbon"]["candidates_count"] += 1 },
      ->(s) { s["lisbon"]["numbered_candidates_count"] += 1 },
      ->(s) { s["lisbon"]["distinct_al_numbers_count"] += 1 },
      ->(s) { s["parishes"][0]["candidates_count"] += 1 },
      ->(s) { s["signals"]["outside_listings"] += 1 },
      ->(s) { s["repeated_number_distances"][0]["count"] += 1 },
      ->(s) { s["repeated_number_distances"].reverse! },
      ->(s) { s["outside_regions"][0]["count"] += 1 }
    ]
    mutations.each do |mutation|
      dataset = CandidateFixture.dataset
      mutation.call(dataset.summary_document)
      assert_raises(ArgumentError) do
        AlojamentoLocal::CandidateDataset.new(summary_document: dataset.summary_document, details_document: dataset.details_document)
      end
    end
  end

  def test_download_copy_detects_changed_bytes_even_for_equivalent_json
    with_pair do |root, path|
      dataset = AlojamentoLocal::CandidateDataset.new(path)
      File.open(File.join(path, "summary.json"), "a") { |io| io.write("\n") }
      assert_raises(ArgumentError) { dataset.copy_downloads(File.join(root, "downloads")) }
      refute File.exist?(File.join(root, "downloads"))
    end
  end

  def test_readers_wait_for_complete_installation_and_interrupt_rolls_back
    PipelineFixture.with_sources do |root, airbnb, official|
      result = PipelineFixture.run(root, airbnb, official)
      path = result[:path]
      original = bytes(path)
      sources = PipelineFixture.pair(airbnb, official)
      dataset = AlojamentoLocal::Analysis::DatasetBuilder.new(sources: sources).build
      publisher = AlojamentoLocal::Analysis::ResultPublisher.new(destination: path)
      real_rename = File.method(:rename)
      entered = Queue.new
      release = Queue.new
      reader_started = Queue.new
      read = Queue.new
      writer = reader = nil
      File.stub(:rename, ->(from, to) {
        value = real_rename.call(from, to)
        if from == path
          entered << true
          release.pop
        end
        value
      }) do
        writer = Thread.new { publisher.publish(dataset: dataset, sources: sources) }
        entered.pop
        reader = Thread.new do
          reader_started << true
          read << AlojamentoLocal::CandidateDataset.new(path).summary
        end
        reader_started.pop
        # A reader attempting the shared lock must wait while the directory is absent.
        Thread.pass until reader.status == "sleep"
        assert read.empty?
        release << true
        writer.value
        reader.value
      end
      assert_equal dataset.summary, read.pop
      assert_equal original, bytes(path)
      File.stub(:rename, ->(from, to) {
        raise Interrupt, "installation interrupted" if to == path && from.include?(".candidate-")
        real_rename.call(from, to)
      }) do
        assert_raises(Interrupt) { publisher.publish(dataset: dataset, sources: sources) }
      end
      assert_equal original, bytes(path)
      assert_empty Dir.glob(File.join(File.dirname(path), ".{candidate,previous}-*"))
    ensure
      release << true if writer&.alive?
      writer&.join
      reader&.join
    end
  end
end
