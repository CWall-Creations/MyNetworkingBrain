require "test_helper"

class ImportersTest < ActiveSupport::TestCase
  SHEET = <<~CSV
    Name,Role,Company,Tags,How we met
    Jamie Park,Data Analyst,Spotify,"Music Streaming, Analytics",Coworker of Aunt
    Riley Chen,Retierd,Retired,Fintech,Aunt
  CSV

  test "spreadsheet rows are parsed with columns from the profile" do
    rows = Importers::SpreadsheetCsv.new(SHEET).rows
    assert_equal 2, rows.size
    assert_equal ["Spotify"], rows[0]["companies"]
    assert_equal "Aunt", rows[0]["introducer"]
    assert_equal "Data Platforms", rows[0]["industry"]
    assert_equal "retired", rows[1]["status"]
  end

  test "applying is idempotent and links hubs" do
    batch = ImportBatch.create!(rows: Importers::SpreadsheetCsv.new(SHEET).rows, format: "spreadsheet")
    Importers::Applier.apply_batch!(batch)
    again = ImportBatch.create!(rows: Importers::SpreadsheetCsv.new(SHEET).rows, format: "spreadsheet")
    Importers::Applier.apply_batch!(again)
    assert_equal 2, Person.count
    aunt = Introducer.find_by(label: "Aunt")
    assert_equal "Riley Chen", aunt.person.name # the "Aunt" row IS the hub
    assert_equal aunt, Person.find_by(name: "Jamie Park").introducer
  end

  test "linkedin export skips the notes preamble" do
    csv = <<~CSV
      Notes:
      "When exporting your connection data, you may notice..."

      First Name,Last Name,URL,Email Address,Company,Position,Connected On
      Sam,Rivera,https://www.linkedin.com/in/sam,,Figma,Software Engineer,12 Mar 2025
    CSV
    assert Importers::LinkedinCsv.linkedin?(csv)
    row = Importers::LinkedinCsv.new(csv).rows.first
    assert_equal "Sam Rivera", row["name"]
    assert_equal ["Figma"], row["companies"]
    assert_equal "2025-03-12", row["met_on"]
  end

  test "export round-trips names and companies" do
    person!("Jamie Park", company: "Spotify")
    csv = CSV.parse(Exporters::Csv.generate, headers: true)
    assert_equal "Spotify", csv.first["Company"]
    # The export's first columns re-import with the default template mapping
    assert_equal "Jamie Park", Importers::SpreadsheetCsv.new(Exporters::Csv.generate).rows.first["name"]
  end
end
