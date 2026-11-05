# Splits a free-text company cell into real employers + a status.
#
#   "Pixel Forge (part-time) & Northwind" => companies ["Pixel Forge", "Northwind"]
#   "Retired/Contoso Labs"     => companies ["Contoso Labs"], status "retired"
#   "Self-employed"            => companies [],             status "self_employed"
#   "State University"         => companies ["State University"], status "student" (if position says student)
class CompanyParser
  Result = Struct.new(:companies, :status, keyword_init: true)

  NON_EMPLOYERS = {
    "self_employed" => /\A\s*(self[\s-]?employed|freelance|freelancer|independent|n\/?a)\s*\z/i,
    "unemployed" => /\A\s*(unemployed|between jobs|looking)\s*\z/i
  }.freeze

  SCHOOL = /\b(university|college|institute of technology|\bUC\b|state univ)/i

  def self.parse(company_text, position: nil) = new.parse(company_text, position:)

  def parse(company_text, position: nil)
    parts = company_text.to_s.gsub(/\([^)]*\)/, " ")
                        .split(%r{\s*(?:&|/|\band\b|,)\s*}i)
                        .map(&:strip).reject(&:empty?)
    status = nil
    companies = parts.each_with_object([]) do |part, acc|
      if (s = non_employer_status(part))
        status ||= s
      else
        acc << part
      end
    end

    status ||= "retired" if retired_word?(position)
    status ||= "student" if position.to_s.match?(/student|phd|masters/i) ||
                            (companies.any? { |c| c.match?(SCHOOL) } && position.to_s.match?(/grad|student/i))
    status ||= "self_employed" if position.to_s.match?(/freelanc|self[\s-]?employed/i)

    Result.new(companies: companies.uniq, status: status || "employed")
  end

  private

  # "Retired", plus common typos of it (anything within 2 edits, e.g. "Retierd").
  def retired_word?(text)
    text.to_s.downcase.scan(/[a-z]+/).any? { |w| w.length.between?(5, 9) && levenshtein(w, "retired") <= 2 }
  end

  def levenshtein(a, b)
    prev = (0..b.length).to_a
    a.each_char.with_index(1) do |ca, i|
      cur = [i]
      b.each_char.with_index(1) { |cb, j| cur << [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca == cb ? 0 : 1)].min }
      prev = cur
    end
    prev.last
  end

  def non_employer_status(part)
    return "retired" if retired_word?(part) && part.split.size == 1
    NON_EMPLOYERS.each { |status, re| return status if part.match?(re) }
    nil
  end
end
