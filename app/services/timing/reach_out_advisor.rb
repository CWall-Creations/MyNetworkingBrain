module Timing
  # Decides who is worth reaching out to *now*, combining:
  #   - industry hiring season (config/hiring_cycles.yml) or a company's openings rising
  #   - the connection cooling off (strength fading)
  #   - enough time since you last talked (profile reach_out.min_gap_days)
  #   - relevance to your target/curious industries or live new-grad roles
  class ReachOutAdvisor
    Nudge = Struct.new(:person, :score, :reason, keyword_init: true)

    def self.cycles = @cycles ||= YAML.load_file(Rails.root.join("config/hiring_cycles.yml"))

    def initialize(today: Date.current, profile: Profile.current)
      @today = today
      @profile = profile
      @strength = StrengthScore.new(half_life_days: profile.half_life_days, today:)
    end

    def season_for(industry)
      cfg = self.class.cycles
      windows = cfg.dig("industries", industry.to_s, "windows") || cfg.dig("default", "windows")
      windows.find { |w| w["months"].include?(@today.month) }
    end

    def quiet? = Array(self.class.cycles["quiet_months"]).include?(@today.month) && @today.day >= 15

    def nudges(people = Person.includes(:companies, :interactions).where(status: %w[employed self_employed]))
      return [] if quiet?
      people.filter_map { |p| evaluate(p) }.sort_by { -_1.score }
    end

    def evaluate(person)
      last = person.last_contact
      days = last ? (@today - last).to_i : nil
      return nil if days && days < @profile.min_gap_days
      return nil unless @strength.cooling?(closeness: person.closeness, last_contact_on: last)

      company = person.primary_company
      new_grad = person.companies.sum { |c| c.relevant_new_grad(@profile).size }
      trend = company&.hiring_trend
      season = season_for(person.industry)
      relevant = @profile.focus_industries.include?(person.industry) || new_grad.positive?
      timing = season || new_grad.positive? || trend.to_f > 0.1
      return nil unless timing && (relevant || person.closeness >= 4)

      score = person.closeness / 5.0 * 0.5 +
              (new_grad.positive? ? 0.25 : 0) + (season ? 0.15 : 0) +
              (@profile.target_buckets.include?(person.industry) ? 0.1 : 0) +
              (trend.to_f > 0.1 ? 0.05 : 0)
      reasons = []
      reasons << "#{new_grad} new-grad role#{'s' if new_grad > 1} open" if new_grad.positive?
      reasons << season["label"] if season
      reasons << "#{company.name} openings up #{(trend * 100).round}%" if trend.to_f > 0.1
      reasons << (days ? "last talked #{days} days ago" : "no contact logged")
      Nudge.new(person:, score: score.round(3), reason: reasons.join(" · "))
    end
  end
end
