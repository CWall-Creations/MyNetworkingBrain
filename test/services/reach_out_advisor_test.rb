require "test_helper"

class ReachOutAdvisorTest < ActiveSupport::TestCase
  def advisor(date, **profile)
    data = { "target_industries" => ["Fintech"], "reach_out" => { "min_gap_days" => 45 } }.merge(profile)
    Timing::ReachOutAdvisor.new(today: date, profile: Profile.new(data))
  end

  test "nudges a cooling contact in a target industry during its hiring season" do
    p = person!("Jordan Rivers", company: "Stripe", industry: "Fintech", closeness: 4)
    p.interactions.create!(occurred_on: Date.new(2026, 5, 1), kind: "call")
    n = advisor(Date.new(2026, 9, 15)).evaluate(p)
    assert n
    assert_match(/fall cycle/i, n.reason)
  end

  test "respects the minimum gap since last contact" do
    p = person!("Jordan Rivers", company: "Stripe", industry: "Fintech", closeness: 4)
    p.interactions.create!(occurred_on: Date.new(2026, 9, 1), kind: "call")
    assert_nil advisor(Date.new(2026, 9, 15)).evaluate(p)
  end

  test "stays quiet out of season with no openings, and over the holidays" do
    p = person!("Jordan Rivers", company: "Stripe", industry: "Fintech", closeness: 4)
    assert_nil advisor(Date.new(2026, 5, 15)).evaluate(p)
    assert_empty advisor(Date.new(2026, 12, 20)).nudges
  end
end
