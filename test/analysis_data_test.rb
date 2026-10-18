require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "stringio"
require_relative "../lib/alojamento_local"

class AnalysisDataTest < Minitest::Test
  Data = AlojamentoLocal::Analysis::Data

  def write_source(root, prefix, date, contents = "header\nrow\n")
    path = File.join(root, "#{prefix}-#{date}.csv")
    File.write(path, contents)
    path
  end

  def test_update_checks_airbnb_but_reuses_newer_rnal_without_downloading
    Dir.mktmpdir do |root|
      airbnb = write_source(root, "listings", "2024-06-01")
      official = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-07-01")
      write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-05-01")
      checks = 0
      latest = -> do
        checks += 1
        ["2024-06-01", "https://example.com/listings.csv.gz"]
      end
      Data.stub(:latest_airbnb_snapshot, latest) do
        URI.stub(:open, ->(*) { flunk "Cached CSVs must not be downloaded" }) do
          2.times { assert_equal [airbnb, official], Data.update!(root: root) }
        end
      end
      assert_equal 2, checks
      assert_equal Date.new(2024, 7, 1), Data.source_date(official)
    end
  end

  def test_same_day_rnal_is_recent_enough
    Dir.mktmpdir do |root|
      official = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-06-01")
      URI.stub(:open, ->(*) { flunk "Same-day RNAL must be reused" }) do
        assert_equal official, Data.prepare_alojamentos_locais!(airbnb_date: Date.new(2024, 6, 1), root: root)
      end
    end
  end

  def test_force_downloads_both_sources_even_when_cached_rnal_is_recent_enough
    Dir.mktmpdir do |root|
      airbnb = write_source(root, "listings", "2024-06-01", "cached airbnb")
      official = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-07-01", "cached rnal")
      older = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-05-01", "historical bytes")
      gzip = StringIO.new
      Zlib::GzipWriter.wrap(gzip) { |gz| gz.write("downloaded airbnb") }
      requests = []
      remote = ->(url, &block) do
        requests << url
        content = case url
        when "https://example.com/listings.csv.gz" then gzip.string
        when Data::OFFICIAL_URL then JSON.generate(resultUrl: "https://example.com/rnal.csv")
        when "https://example.com/rnal.csv" then "downloaded rnal"
        else flunk "Unexpected URL: #{url}"
        end
        block.call(StringIO.new(content))
      end
      Date.stub(:today, Date.new(2024, 7, 1)) do
        Data.stub(:latest_airbnb_snapshot, ["2024-06-01", "https://example.com/listings.csv.gz"]) do
          URI.stub(:open, remote) do
            assert_equal [airbnb, official], Data.update!(root: root, force: true)
          end
        end
      end
      assert_equal ["https://example.com/listings.csv.gz", Data::OFFICIAL_URL, "https://example.com/rnal.csv"], requests
      assert_equal "2024-07-01", Data.manifest(airbnb)["fetched_on"]
      assert_equal "2024-07-01", Data.manifest(official)["fetched_on"]
      assert_equal "downloaded airbnb", File.read(airbnb)
      assert_equal "downloaded rnal", File.read(official)
      assert_equal "historical bytes", File.read(older)
    end
  end

  def test_new_airbnb_download_refreshes_older_rnal_with_actual_download_date
    Dir.mktmpdir do |root|
      old = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-05-01", "old bytes")
      gzip = StringIO.new
      Zlib::GzipWriter.wrap(gzip) { |gz| gz.write("airbnb\nrows\n") }
      requests = []
      remote = ->(url, &block) do
        requests << url
        content = case url
        when "https://example.com/listings.csv.gz" then gzip.string
        when Data::OFFICIAL_URL then JSON.generate(resultUrl: "https://example.com/rnal.csv")
        when "https://example.com/rnal.csv" then "rnal\nrows\n"
        else flunk "Unexpected URL: #{url}"
        end
        block.call(StringIO.new(content))
      end
      Date.stub(:today, Date.new(2024, 7, 1)) do
        Data.stub(:latest_airbnb_snapshot, ["2024-06-01", "https://example.com/listings.csv.gz"]) do
          URI.stub(:open, remote) do
            airbnb, official = Data.update!(root: root)
            assert_equal "airbnb\nrows\n", File.read(airbnb)
            assert_equal "Estabelecimentos_de_Alojamento_Local-2024-07-01.csv", File.basename(official)
            assert_equal "rnal\nrows\n", File.read(official)
          end
        end
      end
      assert_equal ["https://example.com/listings.csv.gz", Data::OFFICIAL_URL, "https://example.com/rnal.csv"], requests
      assert_equal "old bytes", File.read(old)
    end
  end

  def test_local_selection_has_no_network_and_ignores_undated_sources
    Dir.mktmpdir do |root|
      write_source(root, "listings", "2024-05-01")
      airbnb = write_source(root, "listings", "2024-06-01")
      official = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-07-01")
      File.write(File.join(root, "Estabelecimentos_de_Alojamento_Local.csv"), "undated")
      URI.stub(:open, ->(*) { flunk "Local selection must not access the network" }) do
        assert_equal [airbnb, official], Data.local_paths!(root: root)
      end
    end
    Dir.mktmpdir do |root|
      error = assert_raises(RuntimeError) { Data.local_paths!(root: root) }
      assert_includes error.message, "sources:update"
    end
  end

  def test_offline_registration_preserves_unknown_fetch_dates_and_known_manifests
    Dir.mktmpdir do |root|
      airbnb = write_source(root, "listings", "2024-06-01")
      official = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-07-01")
      File.utime(Time.now, Time.now, airbnb)
      URI.stub(:open, ->(*) { flunk "Registration must stay offline" }) do
        first = Data.register!(root: root)
        assert_equal [nil, nil], first.map { |record| record["fetched_on"] }
        assert_equal ["2024-06-01", nil], first.map { |record| record["archive_date"] }
        known = Data.manifest(airbnb, fetched_on: "2024-06-03")
        assert_equal known, Data.manifest(airbnb)
        assert_equal "2024-06-03", Data.register!(root: root).first["fetched_on"]
        File.open(official, "a") { |file| file.write("changed") }
        assert_raises(RuntimeError) { Data.manifest(official) }
      end
    end
  end

  def test_archive_contains_only_selected_pair_and_preserves_bytes
    Dir.mktmpdir do |root|
      write_source(root, "listings", "2024-05-01")
      airbnb = write_source(root, "listings", "2024-06-01")
      official = write_source(root, "Estabelecimentos_de_Alojamento_Local", "2024-07-01")
      destination = File.join(root, "artifact")
      FileUtils.mkdir_p(destination)
      File.write(File.join(destination, "old.csv"), "obsolete")
      assert_equal destination, Data.archive!(root: root, destination: destination)
      assert_equal [airbnb, official].flat_map { |path| [File.basename(path), File.basename(path) + ".manifest.json"] }.sort, Dir.children(destination).sort
      known = Data.manifest(airbnb, fetched_on: "2024-06-03")
      Data.archive!(root: root, destination: destination)
      assert_equal known, Data.manifest(File.join(destination, File.basename(airbnb)))
      assert_nil Data.manifest(File.join(destination, File.basename(official)))["fetched_on"]
      [airbnb, official].each { |path| assert_equal File.binread(path), File.binread(File.join(destination, File.basename(path))) }
    end
  end

  def test_failed_or_empty_download_does_not_leave_a_reusable_source
    Dir.mktmpdir do |root|
      path = File.join(root, "listings-2024-06-01.csv")
      assert_raises(RuntimeError) do
        Data.write_download(path) do |file|
          file.write("partial")
          raise "connection lost"
        end
      end
      assert_empty Dir.children(root)
      assert_raises(RuntimeError) { Data.write_download(path) { |_file| } }
      assert_empty Dir.children(root)
      Data.write_download(path) { |file| file.write("complete") }
      assert_equal "complete", File.read(path)
      assert_equal [File.basename(path)], Dir.children(root)
      assert_raises(RuntimeError) do
        Data.write_download(path) do |file|
          file.write("failed replacement")
          raise "connection lost"
        end
      end
      assert_equal "complete", File.read(path)
    end
  end
end
