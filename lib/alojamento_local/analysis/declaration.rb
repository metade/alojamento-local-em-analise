module AlojamentoLocal
  module Analysis
    # Extract explicit AL declarations without repairing ambiguous fragments.
    class Declaration
      attr_reader :raw, :numbers, :status, :residual
      BOUNDARY = /\A[\p{Space}\p{Cf}]+|[\p{Space}\p{Cf}]+\z/
      TOKEN = /(?<![\p{L}\p{N}\p{M}\p{Cf}_\/.,])(?:([0-9]+)\s*\/\s*AL|AL[\s\/_\-\\&]*([0-9]+))(?![\p{L}\p{N}\p{M}\p{Cf}_\/])/i

      def initialize(raw)
        @raw = raw
        value = raw.to_s.gsub(BOUNDARY, "")
        @numbers = []
        @residual = ""
        single = AlojamentoLocal.parse_al_license(value)
        # The single-value parser also handles historical whole-value formats.
        if single && single != "0" && value.match?(/\A(?:(?:Registration Number:\s*)?[0-9]+(?:[\/\s_\-\\&]*al\.?|\s*\/\s*20[12][0-9])?|al[\/\s_\-\\&]*[0-9]+)\z/i)
          @numbers = [single]
        else
          @residual = value.gsub(TOKEN) do
            match = Regexp.last_match
            # Never extract the last group of a thousands-separated number.
            if match.pre_match.match?(/[0-9][.,\p{Space}]+\z/) || (match[2] && match.post_match.match?(/\A[.,\p{Space}]+[0-9]/))
              match[0]
            else
              number = (match[1] || match[2]).to_i.to_s
              @numbers << number unless number == "0"
              (number == "0") ? match[0] : " "
            end
          end
          @numbers = numbers.uniq.sort_by(&:to_i)
        end
        @status = if numbers.any?
          "numbered"
        elsif value.empty?
          "absent"
        elsif value.match?(/\A(?:exempt|isento|isenta|isento de registo|isenta de registo)\z/i)
          "exempt"
        else
          "unrecognised"
        end
      end

      def partial?
        numbers.any? && residual.match?(/[\p{L}\p{N}]/)
      end
    end
  end
end
