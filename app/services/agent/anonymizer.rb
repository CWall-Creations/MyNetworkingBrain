module Agent
  # Replaces contacts' names with tokens (P-007) before anything is sent to Claude,
  # and swaps them back in the response. Your own name becomes [ME].
  # Companies, positions and industries are sent as-is.
  class Anonymizer
    MIN_PART = 3

    def initialize(people: Person.all, me: Profile.current.name)
      @people = people.to_a
      @me = me
      @by_token = @people.index_by { |p| token(p) }
    end

    def token(person) = format("P-%03d", person.id)

    def scrub(text)
      out = text.to_s.dup
      # Full names first (longest first so "Jordan Smith" wins over "Jordan")
      @people.sort_by { |p| -p.name.length }.each do |p|
        out.gsub!(/\b#{Regexp.escape(p.name)}\b/i, token(p))
      end
      out.gsub!(/\b#{Regexp.escape(@me)}\b/i, "[ME]") if @me.present? && @me != "Me"
      # Then any leftover first/last name parts
      name_parts.each { |part| out.gsub!(/\b#{Regexp.escape(part)}\b/, "[name]") }
      out
    end

    # Scrubs contacts' names only (used on your own resume, where your name is wanted).
    def scrub_contacts(text)
      out = text.to_s.dup
      @people.sort_by { |p| -p.name.length }.each do |p|
        next if p.name.split.size < 2 # single first names are too ambiguous to scrub safely
        out.gsub!(/\b#{Regexp.escape(p.name)}\b/i, token(p))
      end
      out
    end

    def restore(text)
      text.to_s.gsub(/P-\d{3,}/) { |t| @by_token[t]&.name || t }
    end

    private

    def name_parts
      @name_parts ||= begin
        parts = @people.flat_map { |p| p.name.scan(/[[:alpha:]'-]+/) }
        parts += @me.to_s.scan(/[[:alpha:]'-]+/) unless @me == "Me"
        parts.select { |w| w.length >= MIN_PART && w.match?(/\A[[:upper:]]/) }.uniq.sort_by { -_1.length }
      end
    end
  end
end
