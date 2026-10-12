module AlojamentoLocal
  module Geography
    PARISHES = ["Ajuda", "Alcântara", "Alvalade", "Areeiro", "Arroios", "Avenidas Novas", "Beato", "Belém", "Benfica", "Campo de Ourique", "Campolide", "Carnide", "Estrela", "Lumiar", "Marvila", "Misericórdia", "Olivais", "Parque das Nações", "Penha de França", "Santa Clara", "Santa Maria Maior", "Santo António", "São Domingos de Benfica", "São Vicente"].freeze
    ALIASES = {"Alcntara" => "Alcântara", "Belm" => "Belém", "Misericrdia" => "Misericórdia", "Parque das Naes" => "Parque das Nações", "Penha de Frana" => "Penha de França", "Santo Antnio" => "Santo António", "So Domingos de Benfica" => "São Domingos de Benfica", "So Vicente" => "São Vicente"}.freeze
    UNKNOWN = "Geografia não identificada"
    def self.key(value)
      value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").strip.downcase.gsub(/\s+/, " ")
    end
    def self.municipality(value)
      text = value.to_s.strip
      return nil if text.empty? || key(text).match?(/\A(?:unknown|desconhecid[oa]|nao identificad[oa]|nao disponivel|n\/a|null|nd|-)\z/)
      key(text) == "lisboa" ? "Lisboa" : text
    end
    PARISH_KEYS = PARISHES.to_h { |name| [key(name), name] }.freeze
    def self.display_name(value)
      ALIASES.fetch(value.to_s, value.to_s)
    end

    def self.route_name(value)
      ALIASES.key(value) || value
    end

    def self.parish(value)
      text = ALIASES.fetch(value.to_s.strip, value.to_s.strip)
      PARISH_KEYS.fetch(key(text), UNKNOWN)
    end
  end

end
