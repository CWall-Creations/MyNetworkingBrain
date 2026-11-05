# Turns free-text "how we met" notes into structure:
#
#   "Work Friend of Uncle"        => introducer "Uncle",        context "work"
#   "Friend of a Neighbor"        => introducer "Neighbor"
#   "Brother of college roommate" => introducer "College Roommate", relation "brother"
#   "LinkedIn (career fair)"      => direct, context "linkedin"
#   "Uncle"                       => direct, family, and this person IS the "Uncle" hub
#
# Generic on purpose: no names or personal relationships are hardcoded.
class HowMetParser
  Result = Struct.new(:introducer, :context, :relation, :self_label, keyword_init: true) do
    def direct? = introducer.nil?
  end

  # Words that name a relative/relationship. If how_met is *just* one of these,
  # the person themselves is that hub (e.g. how_met "Uncle" => they are "Uncle").
  RELATIVE_ALIASES = {
    "father" => "Dad", "dad" => "Dad", "mother" => "Mom", "mom" => "Mom",
    "uncle" => "Uncle", "aunt" => "Aunt", "brother" => "Brother", "sister" => "Sister",
    "cousin" => "Cousin", "grandfather" => "Grandpa", "grandmother" => "Grandma",
    "grandpa" => "Grandpa", "grandma" => "Grandma"
  }.freeze

  CONTEXT_KEYWORDS = {
    "linkedin" => /\blinked\s?in\b/i,
    "work" => /\b(work|boss|coworker|co-worker|colleague|partner|intern|manager)\b/i,
    "volunteer" => /\bvolunteer/i,
    "sport" => /\b(sport|team|club|league|gym)\b/i,
    "school" => /\b(college|school|university|class|alumni|alum)\b/i,
    "event" => /\b(conference|hackathon|career fair|event|meetup)\b/i,
    "roommate" => /\broommate/i,
    "family" => /\bfamily\b/i,
    "personal" => /\b(personal|friend)\b/i
  }.freeze

  ARTICLES = /\A(a|an|the|my)\s+/i

  def self.parse(text) = new.parse(text)

  def parse(text)
    raw = text.to_s.strip
    return Result.new if raw.empty?

    if (label = relative_label(raw))
      return Result.new(context: "family", self_label: label)
    end

    # Ignore parentheticals like "LinkedIn (career fair)" when looking for " of "
    core = raw.gsub(/\([^)]*\)/, " ").squeeze(" ").strip
    relation, introducer = split_on_of(core)

    Result.new(
      introducer: introducer && normalize_label(introducer),
      relation: relation && relation_word(relation),
      context: context_for(raw)
    )
  end

  private

  def relative_label(text)
    RELATIVE_ALIASES[text.downcase.delete_prefix("my ").strip]
  end

  def split_on_of(text)
    idx = text.downcase.rindex(" of ")
    return [nil, nil] unless idx
    [text[0...idx].strip, text[(idx + 4)..].strip]
  end

  def normalize_label(label)
    cleaned = label.sub(ARTICLES, "").strip
    alias_label = RELATIVE_ALIASES[cleaned.downcase]
    return alias_label if alias_label
    # "college roommate" / "mom's coworker" -> title-ish case, keep apostrophes
    cleaned.split(/\s+/).map { |w| w.match?(/\A[A-Z]{2,}\z/) ? w : w.capitalize }.join(" ")
  end

  def relation_word(before_of)
    word = before_of.split(%r{[\s/]+}).last.to_s.downcase
    word.empty? ? nil : word
  end

  def context_for(text)
    CONTEXT_KEYWORDS.each { |ctx, re| return ctx if text.match?(re) }
    nil
  end
end
