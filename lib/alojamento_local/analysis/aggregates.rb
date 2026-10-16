# frozen_string_literal: true

require "time"

module AlojamentoLocal
  module Analysis
    module Aggregates
      module_function

      def licence_groups(listings)
        listings.group_by { |row| [row[:licensa].to_s, row[:license_group_assessment].to_s] }.map do |(license, _assessment), rows|
          first = rows.first
          {
            licensa: license, licence_raw_examples: rows.map { |row| row[:licensa_raw] }.compact.uniq.join(" | "),
            listings: rows.size, spatial_locations: license.empty? ? 0 : first[:spatial_cluster_count],
            classification: first[:license_group_assessment], official_name: first[:official_name],
            official_concelho: first[:official_concelho], official_modalidade: first[:official_modalidade],
            establishment_estimate: AlojamentoLocal.establishment_estimate(rows)
          }
        end.sort_by { |row| row[:licensa] }
      end

      def public_listing_rows(listings)
        listings.group_by { |row| [row[:bairro].to_s, row[:license_group_assessment].to_s] }.map do |(freguesia, classification), rows|
          {freguesia: freguesia, classification: classification, **announcement_totals(rows)}
        end.sort_by { |row| [row[:freguesia], row[:classification]] }
      end

      def public_group_rows(groups)
        groups.group_by do |group|
          [group[:classification].to_s, public_municipality(group[:official_concelho]), public_type(group[:official_modalidade])]
        end.map do |(classification, municipality, type), rows|
          {
            classification: classification,
            official_municipality: municipality,
            official_type: type,
            licence_groups: rows.count { |row| !row[:licensa].to_s.empty? },
            announcements: rows.sum { |row| row[:listings].to_i },
            spatial_locations: rows.sum { |row| row[:spatial_locations].to_i },
            estimated_establishments: rows.sum { |row| row[:establishment_estimate].to_i }
          }
        end.sort_by { |row| [row[:classification], row[:official_municipality], row[:official_type]] }
      end

      def public_municipality(value)
        return "não identificado" if value.to_s.empty?
        (value == "Lisboa") ? "Lisboa" : "outro município"
      end

      def public_type(value)
        text = value.to_s
        return "não identificado" if text.empty?
        return "hospedagem" if text.match?(/Hospedagem|Hostel|Quartos/i)
        return "apartamento" if text.match?(/Apartamento|Moradia|Casa/i)

        "outro tipo"
      end

      def freguesia_rows(listings)
        grouped = listings.group_by { |row| row[:bairro].to_s }
        Geography::PARISHES.each { |name| grouped[name] ||= [] }
        grouped.map do |name, rows|
          {freguesia: name, **announcement_totals(rows)}
        end.sort_by { |row| row[:freguesia] }
      end

      def summary(listings, groups, dates, run_id, mode, official: {})
        identified_groups = groups.reject { |group| group[:licensa].to_s.empty? }
        counts = identified_groups.group_by { |group| group[:classification] }.transform_values(&:size)
        {
          run_id: run_id, source_dates: dates, methodology_version: METHODOLOGY_VERSION,
          listings: listings.size, licence_groups: identified_groups.size,
          official_registers_lisbon: official_lisbon_count(official),
          establishment_estimate: AlojamentoLocal.establishment_estimate(listings),
          classifications: counts, mode: mode, generated_at: Time.now.utc.iso8601
        }
      end

      def announcement_totals(rows)
        {
          announcements: rows.size,
          announcements_with_identifiable_number: AnnouncementCounts.calculate(rows)[:identifiable_number],
          estimated_establishments: AlojamentoLocal.establishment_estimate(rows)
        }
      end

      def official_lisbon_count(official)
        return official.lisbon_entries.size if official.is_a?(PreparedSources::Official)

        official.values.count { |record| record["Concelho"] == "Lisboa" }
      end

      private_class_method :announcement_totals, :official_lisbon_count
    end
  end
end
