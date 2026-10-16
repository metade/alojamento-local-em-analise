require "uri"
require "zlib"
require "open-uri"
require "date"
require "json"
require "fileutils"
require "tempfile"
require "digest"

module AlojamentoLocal
  module Analysis
    module Data
      AIRBNB_DATA_PAGE = "https://insideairbnb.com/get-the-data/"
      OFFICIAL_URL = "https://hub.arcgis.com/api/download/v1/items/4e62eb1977564991bd01e61d7aa8266f/csv?redirect=false&layers=6"

      def self.airbnb_url(date)
        "https://data.insideairbnb.com/portugal/lisbon/lisbon/#{date}/data/listings.csv.gz"
      end

      def self.update!(root: "data_sources", force: false)
        airbnb = prepare_airbnb!(root: root, force: force)
        [airbnb, prepare_alojamentos_locais!(airbnb_date: source_date(airbnb), root: root, force: force)]
      end

      # Analysis selects dated local files without contacting either source.
      def self.local_paths!(root: "data_sources")
        airbnb = latest_local("listings", root: root)
        official = latest_local("Estabelecimentos_de_Alojamento_Local", root: root)
        raise "Missing dated local sources; run bundle exec rake sources:update first" unless airbnb && official

        [airbnb, official]
      end

      # Resolve and verify local source bytes recorded by a validated snapshot.
      def self.local_paths_for_snapshot!(snapshot, root: "data_sources")
        metadata = snapshot.fetch("metadata")
        run_id = metadata.fetch("run_id")
        dates = metadata.fetch("source_dates")
        paths = {
          "airbnb" => File.join(root, "listings-#{dates.fetch('airbnb_snapshot_date')}.csv"),
          "official" => File.join(root, "Estabelecimentos_de_Alojamento_Local-#{dates.fetch('official_register_download_date')}.csv")
        }
        paths.each do |source, path|
          raise "Missing source for #{run_id}: #{path}" unless File.file?(path)
          unless Digest::SHA256.file(path).hexdigest == metadata.fetch("source_files").fetch(source).fetch("sha256")
            raise "Source bytes differ from selected run #{run_id}: #{source} (#{path})"
          end
        end
        paths.values_at("airbnb", "official")
      end

      def self.source_date(path)
        Date.iso8601(File.basename(path)[/(\d{4}-\d{2}-\d{2})\.csv\z/, 1])
      end

      def self.latest_local(prefix, root:)
        Dir.glob(File.join(root, "#{prefix}-????-??-??.csv")).select { |path| File.file?(path) }
          .max_by { |path| source_date(path) }
      end

      def self.prepare_alojamentos_locais!(airbnb_date:, root: "data_sources", force: false)
        existing = latest_local("Estabelecimentos_de_Alojamento_Local", root: root)
        return existing if !force && existing && source_date(existing) >= airbnb_date

        date = Date.today
        raise "Airbnb snapshot date is in the future: #{airbnb_date}" if airbnb_date > date
        path = File.join(root, "Estabelecimentos_de_Alojamento_Local-#{date}.csv")

        download_data = URI.open(OFFICIAL_URL) do |remote_file|
          JSON.parse(remote_file.read)
        end
        csv_url = download_data["resultUrl"]

        write_download(path) do |file|
          URI.open(csv_url) { |remote_file| IO.copy_stream(remote_file, file) }
        end

        path
      end

      def self.prepare_airbnb!(root: "data_sources", force: false)
        date, airbnb_data_url = latest_airbnb_snapshot
        path = File.join(root, "listings-#{date}.csv")
        puts "Using latest available Airbnb snapshot from #{date}: #{airbnb_data_url}"
        return path if !force && File.exist?(path)
        puts "  ... downloading airbnb data"

        write_download(path) do |file|
          URI.open(airbnb_data_url) do |remote_file|
            Zlib::GzipReader.wrap(remote_file) { |gz| IO.copy_stream(gz, file) }
          end
        end

        path
      end

      # A failed download must never leave a dated file that looks reusable.
      def self.write_download(path)
        FileUtils.mkdir_p(File.dirname(path))
        Tempfile.create([".download-", ".csv"], File.dirname(path)) do |file|
          yield file
          file.flush
          raise "Empty source download: #{path}" if file.size.zero?
          File.rename(file.path, path)
        end
      end

      def self.archive!(root: "data_sources", destination: "tmp/source-artifact")
        paths = local_paths!(root: root)
        FileUtils.mkdir_p(destination)
        # Only stage the selected pair, never historical or unrelated files.
        Dir.glob(File.join(destination, "*.csv")).each { |path| FileUtils.rm_f(path) }
        paths.each { |path| FileUtils.cp(path, destination) }
        destination
      end

      def self.latest_airbnb_snapshot(page = nil)
        page ||= URI.open(AIRBNB_DATA_PAGE).read
        lisbon_section = page[/<h3[^>]*>\s*Lisbon.*?<\/h3>(.*?)(?=<h3|\z)/mi, 1]
        raise "Could not find Lisbon on the Inside Airbnb data page" unless lisbon_section

        links = lisbon_section.scan(/href=["']([^"']*listings\.csv\.gz)["']/i).flatten
        link = links.select { |url| url.match?(%r{/portugal/lisbon/lisbon/\d{4}-\d{2}-\d{2}/data/listings\.csv\.gz\z}i) }.max_by { |url| url[%r{/((?:19|20)\d{2}-\d{2}-\d{2})/}, 1] }
        raise "Could not find Lisbon listings.csv.gz on the Inside Airbnb data page" unless link

        date_text = link[%r{/((?:19|20)\d{2}-\d{2}-\d{2})/}, 1]
        date_text ||= lisbon_section[/<h4[^>]*>.*?((?:19|20)\d{2}-\d{2}-\d{2}|\d{1,2}\s+[A-Za-z]+,?\s+\d{4}).*?<\/h4>/mi, 1]
        date = Date.parse(date_text.to_s)

        [date.to_s, link]
      rescue ArgumentError, Date::Error
        raise "Could not parse the Lisbon snapshot date from the Inside Airbnb data page"
      end
    end
  end
end
