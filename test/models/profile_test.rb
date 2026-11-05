require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "role matching ignores other engineering disciplines" do
    p = Profile.new("target_roles" => ["Software Engineer", "ML Engineer"])
    assert p.role_match?("Software Engineer, New Grad")
    assert p.role_match?("Backend Engineer Graduate")
    refute p.role_match?("Electrical Engineer 1 (Onsite)")
    refute p.role_match?("Mechanical Engineer I")
    assert Profile.new("target_roles" => ["Electrical Engineer"]).role_match?("Electrical Engineer 1")
  end

  test "free-text industries map onto buckets" do
    p = Profile.new("target_industries" => ["ML startups", "Pro sports tech", "Big Tech companies"])
    assert_equal ["AI/ML", "Sports Tech"], p.target_buckets
  end
end
