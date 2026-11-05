require "test_helper"

class HowMetParserTest < ActiveSupport::TestCase
  def parse(t) = HowMetParser.parse(t)

  test "friend of a relative becomes an introducer hub with context" do
    r = parse("Coworker of Aunt")
    assert_equal "Aunt", r.introducer
    assert_equal "work", r.context
  end

  test "strips articles and normalizes relatives" do
    assert_equal "Neighbor", parse("Friend of a Neighbor").introducer
    assert_equal "Mom", parse("Teammate of Mother").introducer
    assert_equal "College Roommate", parse("Brother of college roommate").introducer
    assert_equal "sport", parse("Club/Team Friend of Mom").context
  end

  test "direct connections have no introducer" do
    r = parse("LinkedIn (career fair)")
    assert r.direct?
    assert_equal "linkedin", r.context
    assert parse("Personal Friend").direct?
    assert_equal "work", parse("My Manager").context
  end

  test "a bare relationship means the person IS that hub" do
    r = parse("Aunt")
    assert_equal "Aunt", r.self_label
    assert r.direct?
  end
end
