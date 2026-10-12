require "uri"
require "zlib"
require "open-uri"
require "date"
require "json"
require "fileutils"

module AlojamentoLocal
  module Analysis
    module Data
      AIRBNB_DATA_PAGE = "https://insideairbnb.com/get-the-data/"
      OFFICIAL_URL = "https://hub.arcgis.com/api/download/v1/items/4e62eb1977564991bd01e61d7aa8266f/csv?redirect=false&layers=6"

      def self.airbnb_url(date)
        "https://data.insideairbnb.com/portugal/lisbon/lisbon/#{date}/data/listings.csv.gz"
      end

      def self.prepare!
        [prepare_airbnb!, prepare_alojamentos_locais!]
      end

      def self.prepare_alojamentos_locais!
        date = Date.today
        path = "data_sources/Estabelecimentos_de_Alojamento_Local-#{date}.csv"
        return path if File.exist?(path)

        download_data = URI.open(OFFICIAL_URL) do |remote_file|
          JSON.parse(remote_file.read)
        end
        csv_url = download_data["resultUrl"]

        FileUtils.mkdir_p(File.dirname(path))
        URI.open(csv_url) do |remote_file|
          File.write(path, remote_file.read)
        end

        path
      end

      def self.prepare_airbnb!
        date, airbnb_data_url = latest_airbnb_snapshot
        path = "data_sources/listings-#{date}.csv"
        puts "Using latest available Airbnb snapshot from #{date}: #{airbnb_data_url}"
        return path if File.exist?(path)
        puts "  ... downloading airbnb data"

        FileUtils.mkdir_p(File.dirname(path))
        URI.open(airbnb_data_url) do |remote_file|
          Zlib::GzipReader.wrap(remote_file) do |gz|
            File.write(path, gz.read)
          end
        end

        path
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
