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

      # Register cached bytes offline; a filename is not proof of a fetch date.
      def self.register!(root: "data_sources")
        paths = %w[listings Estabelecimentos_de_Alojamento_Local].flat_map do |prefix|
          Dir.glob(File.join(root, "#{prefix}-????-??-??.csv")).sort
        end
        raise "Missing dated local sources" if paths.empty?
        paths.map { |path| manifest(path) }
      end

      def self.manifest(path, fetched_on: nil, url: nil)
        filename = "#{path}.manifest.json"
        hash = Digest::SHA256.file(path).hexdigest
        if File.file?(filename) && fetched_on.nil?
          record = JSON.parse(File.read(filename))
          raise "Source manifest hash differs: #{path}" unless record.fetch("sha256") == hash
          raise "Source manifest filename differs: #{path}" unless record.fetch("filename") == File.basename(path)
          raise "Source manifest date differs: #{path}" unless record.fetch("source_file_date") == source_date(path).to_s
          Date.iso8601(record["fetched_on"]) if record["fetched_on"]
          expected_archive = File.basename(path).start_with?("listings-") ? source_date(path).to_s : nil
          raise "Source manifest archive date differs: #{path}" unless record.fetch("archive_date") == expected_archive
          return record
        end
        airbnb = File.basename(path).start_with?("listings-")
        date = source_date(path).to_s
        record = {"filename" => File.basename(path), "sha256" => hash,
                  "url" => url || (airbnb ? airbnb_url(date) : OFFICIAL_URL),
                  "source_file_date" => date, "archive_date" => airbnb ? date : nil,
                  "fetched_on" => fetched_on}
        Tempfile.create([".manifest-", ".json"], File.dirname(path)) do |file|
          file.write(JSON.pretty_generate(record) + "\n")
          file.flush
          File.rename(file.path, filename)
        end
        record
      end

      def self.source_date(path)
        Date.iso8601(File.basename(path)[/(\d{4}-\d{2}-\d{2})\.csv\z/, 1])
      end

      def self.latest_local(prefix, root:)
        Dir.glob(File.join(root, "#{prefix}-????-??-??.csv")).select { |path| File.file?(path) }
          .max_by { |path| source_date(path) }
      end

      # Source URLs are HTTPS endpoints; open-uri performs the downloads.
      # standard:disable Security/Open
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

        manifest(path, fetched_on: Date.today.to_s, url: OFFICIAL_URL)
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

        manifest(path, fetched_on: Date.today.to_s, url: airbnb_data_url)
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
        Dir.glob(File.join(destination, "*")).each { |path| FileUtils.rm_f(path) }
        paths.each do |path|
          record = manifest(path)
          FileUtils.cp([path, "#{path}.manifest.json"], destination)
          copied = File.join(destination, File.basename(path))
          raise "Source changed during archive: #{path}" unless Digest::SHA256.file(copied).hexdigest == record.fetch("sha256")
        end
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
      rescue ArgumentError
        raise "Could not parse the Lisbon snapshot date from the Inside Airbnb data page"
      end
      # standard:enable Security/Open
    end
  end
end
