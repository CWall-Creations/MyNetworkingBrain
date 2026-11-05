require "test_helper"

class StrengthScoreTest < ActiveSupport::TestCase
  setup { @s = StrengthScore.new(half_life_days: 100, today: Date.new(2026, 11, 4)) }

  test "fresh contact keeps full closeness" do
    assert_in_delta 1.0, @s.call(closeness: 5, last_contact_on: Date.new(2026, 11, 4)), 0.001
  end

  test "decays by half (above the floor) every half-life" do
    s = @s.call(closeness: 5, last_contact_on: Date.new(2026, 11, 4) - 100)
    assert_in_delta 0.2 + 0.8 * 0.5, s, 0.001
  end

  test "never decays below the floor" do
    assert_in_delta 0.2, @s.call(closeness: 5, last_contact_on: Date.new(2000, 1, 1)), 0.001
  end

  test "unknown recency is neutral and recent interactions add a bonus" do
    assert_in_delta 0.6 * 0.6, @s.call(closeness: 3, last_contact_on: nil), 0.001
    assert @s.call(closeness: 3, last_contact_on: Date.new(2026, 11, 1), recent_interactions: 2) >
           @s.call(closeness: 3, last_contact_on: Date.new(2026, 11, 1))
  end

  test "cooling" do
    assert @s.cooling?(closeness: 3, last_contact_on: Date.new(2026, 6, 1))
    refute @s.cooling?(closeness: 3, last_contact_on: Date.new(2026, 10, 30))
    refute @s.cooling?(closeness: 1, last_contact_on: nil)
  end
end
