# Hybrid connection strength in 0.0..1.0
#
#   strength = closeness/5 * recency
#   recency  = floor + (1 - floor) * 0.5 ** (days_since_contact / half_life)
#
# - closeness (1-5) is your own rating.
# - recency fades as time passes without an interaction; logging one refreshes it.
# - People with no known contact date get a neutral recency (UNKNOWN_RECENCY).
class StrengthScore
  FLOOR = 0.2              # a close friend never decays to zero
  UNKNOWN_RECENCY = 0.6
  RECENT_BONUS_DAYS = 30   # interactions in the last 30 days add a small bonus
  RECENT_BONUS = 0.05      # per interaction, capped

  def initialize(half_life_days: 120, today: Date.current)
    @half_life = half_life_days.to_f
    @today = today
  end

  def call(closeness:, last_contact_on:, recent_interactions: 0)
    base = closeness.to_i.clamp(1, 5) / 5.0
    bonus = [recent_interactions.to_i * RECENT_BONUS, 0.15].min
    (base * recency(last_contact_on) + bonus).clamp(0.0, 1.0).round(3)
  end

  def recency(last_contact_on)
    return UNKNOWN_RECENCY if last_contact_on.nil?
    days = (@today - last_contact_on.to_date).to_i.clamp(0, 10_000)
    FLOOR + (1 - FLOOR) * (0.5**(days / @half_life))
  end

  # "Cooling" = you used to be close-ish but haven't talked in a while.
  def cooling?(closeness:, last_contact_on:)
    closeness.to_i >= 2 && (last_contact_on.nil? || recency(last_contact_on) < 0.7)
  end

  def self.label(score)
    case score
    when 0.7.. then "strong"
    when 0.4...0.7 then "steady"
    else "faint"
    end
  end
end
