# Offline fallback: picks the bucket from config/industries.yml whose keywords
# best match a person's tags/position/company. The agent overrides this when
# an API key is configured.
class IndustryClassifier
  def self.buckets
    @buckets ||= YAML.load_file(Rails.root.join("config/industries.yml")).fetch("buckets")
  end

  def self.names = buckets.keys

  # First argument (your own tags) wins; the rest are only used if tags match nothing.
  def self.classify(tags, *fallback_texts)
    from_tags = best_match(Array(tags).join(" "))
    return from_tags if from_tags
    best_match(fallback_texts.flatten.compact.join(" ")) || "Other"
  end

  def self.best_match(text)
    best = buckets.map do |bucket, kws|
      hits = Array(kws).count { |kw| text.match?(/(?<![a-z])#{Regexp.escape(kw)}/i) }
      [bucket, hits]
    end.max_by { |(_, hits)| hits }
    best && best[1].positive? ? best[0] : nil
  end
end
