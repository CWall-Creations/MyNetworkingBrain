require "csv"

module Exporters
  # Your whole network as a CSV (same columns as the spreadsheet import).
  module Csv
    # First five columns match the default spreadsheet import, so an export re-imports cleanly.
    HEADERS = ["Name", "Role", "Company", "Tags", "How we met",
               "Industry", "Closeness", "Strength", "Last Contact", "Notes"].freeze

    module_function

    def generate(people = Person.includes(:companies, :interactions).order(:name))
      CSV.generate do |csv|
        csv << HEADERS
        people.each do |p|
          csv << [p.name, p.position, p.company_names, Array(p.industry_tags).join(", "), p.how_met,
                  p.industry, p.closeness, p.strength, p.last_contact, p.notes]
        end
      end
    end
  end
end
