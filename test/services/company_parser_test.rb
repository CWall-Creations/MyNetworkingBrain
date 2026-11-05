require "test_helper"

class CompanyParserTest < ActiveSupport::TestCase
  test "splits multiple employers and drops parentheticals" do
    r = CompanyParser.parse("Pixel Forge (w/ a friend) & Northwind")
    assert_equal ["Pixel Forge", "Northwind"], r.companies
    assert_equal "employed", r.status
  end

  test "retired entries, including typos" do
    assert_equal ["Contoso Labs"], CompanyParser.parse("Retired/Contoso Labs").companies
    assert_equal "retired", CompanyParser.parse("Retired/Contoso Labs").status
    r = CompanyParser.parse("Retired", position: "Retierd")
    assert_empty r.companies
    assert_equal "retired", r.status
    assert_equal "employed", CompanyParser.parse("Fabrikam", position: "Engineer").status
  end

  test "self-employed and students" do
    assert_equal "self_employed", CompanyParser.parse("Self-employed").status
    assert_equal "student", CompanyParser.parse("State University", position: "Grad Student").status
  end
end
