module Jobs
  # Guesses which public ATS board a company uses by trying slug variants.
  # A detected board is marked unverified; you can confirm or fix it on the Companies page.
  class AtsDetector
    ORDER = %w[greenhouse ashby lever].freeze

    def self.slug_candidates(name)
      base = name.to_s.downcase.gsub(/\b(inc|llc|corp|corporation|co|ltd|technologies|the)\b\.?/, "").strip
      words = base.scan(/[a-z0-9]+/)
      return [] if words.empty?
      # Never try just the first word: "Open Road Labs" -> "open" would match an unrelated board.
      [words.join, words.join("-")].uniq
    end

    # Returns [provider, slug, postings] or nil.
    def self.detect(name)
      slug_candidates(name).each do |slug|
        ORDER.each do |provider|
          postings = Boards::PROVIDERS[provider].fetch(slug)
          return [provider, slug, postings] if postings # an empty board still counts as found
        end
      end
      nil
    end
  end
end
