module Jobs
  # Decides whether a posting is a new grad / entry-level role.
  class NewGradFilter
    INCLUDE = [
      /new\s*grad/i, /new\s*college\s*grad/i, /\bNCG\b/, /university\s*(grad|hire|recruit)/i,
      /early[\s-]*career/i, /entry[\s-]*level/i, /\bjunior\b/i, /\bassociate\s+(software|engineer|data|product)/i,
      /graduate\s+(engineer|program|software|analyst)/i, /\b(20(2[6-9]|3\d))\s*(grad|start)/i,
      /\b(?i:engineer|developer|analyst|scientist)\s+(I|1)\b(?!\s*I)/, /\blevel\s*1\b/i, /rotational/i,
      /class of 20\d\d/i, /campus/i
    ].freeze

    EXCLUDE = [
      /\b(senior|sr\.?|staff|principal|lead|director|manager|head of|vp|chief|architect)\b/i,
      /\bintern(ship)?\b/i, /\b(II|III|IV|2|3|4)\s*$/, /co-?op/i, /\bphd\b/i
    ].freeze

    def self.new_grad?(title, description = nil)
      text = title.to_s
      return false if EXCLUDE.any? { |re| text.match?(re) }
      return true if INCLUDE.any? { |re| text.match?(re) }
      description.to_s[0, 3000].match?(/new grad|recent graduate|0-1 years|0\+ years|graduating in 20\d\d/i)
    end
  end
end
