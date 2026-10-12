require_relative "../analysis"

module AlojamentoLocal
  module Analysis
    module AnnouncementCounts
      def self.calculate(rows, national: nil)
        counts = {announcements: rows.size, empty_licence: 0, unrecognised_licence: 0, identifiable_number: 0}
        counts[:confirmed_rnal_match] = 0 if national
        rows.each do |row|
          empty = row[:licensa_raw].to_s.strip.empty?
          counts[:empty_licence] += 1 if empty
          counts[:unrecognised_licence] += 1 if !empty && !row[:licensa]
          counts[:identifiable_number] += 1 if row[:licensa]
          counts[:confirmed_rnal_match] += 1 if national && row[:licensa] && national.key?(row[:licensa])
        end
        counts
      end
    end
  end
end
