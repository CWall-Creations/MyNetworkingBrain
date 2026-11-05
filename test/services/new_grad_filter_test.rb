require "test_helper"

class NewGradFilterTest < ActiveSupport::TestCase
  YES = ["Software Engineer, New Grad", "Software Engineer – New Grad (2027)", "Early Career Data Analyst",
         "Associate Software Engineer", "Software Engineer I", "University Graduate - ML Engineer",
         "Entry Level Systems Engineer", "Junior Developer"].freeze
  NO = ["Senior Software Engineer", "Staff ML Engineer", "Software Engineer II", "Engineering Manager",
        "Software Engineering Intern", "Principal Engineer, New Grad Programs"].freeze

  test "includes new grad titles" do
    YES.each { |t| assert Jobs::NewGradFilter.new_grad?(t), t }
  end

  test "excludes senior / intern titles" do
    NO.each { |t| refute Jobs::NewGradFilter.new_grad?(t), t }
  end

  test "falls back to the description" do
    assert Jobs::NewGradFilter.new_grad?("Software Engineer", "Ideal for recent graduates graduating in 2027")
    refute Jobs::NewGradFilter.new_grad?("Software Engineer", "5+ years experience")
  end
end
