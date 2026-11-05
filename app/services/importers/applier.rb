module Importers
  # Upserts reviewed rows into the DB. Matching is by name + company so
  # re-importing an updated sheet never duplicates anyone.
  module Applier
    module_function

    def match(name, companies)
      candidates = Person.where("lower(name) = ?", name.to_s.strip.downcase).includes(:companies).to_a
      return nil if candidates.empty?
      norm = Array(companies).map { |c| Company.normalize(c) }
      candidates.find { |p| (p.companies.map(&:normalized_name) & norm).any? } ||
        (candidates.size == 1 ? candidates.first : nil)
    end

    def apply_row!(row, source:)
      row = row.stringify_keys
      person = (row["existing_id"].presence && Person.find_by(id: row["existing_id"])) ||
               match(row["name"], row["companies"]) || Person.new(source:)
      Person.transaction do
        person.assign_attributes(
          name: row["name"], position: row["position"], status: row["status"].presence || "employed",
          industry: row["industry"].presence || person.industry,
          industry_tags: Array(row["industry_tags"]), closeness: row["closeness"].to_i.clamp(1, 5),
          notes: row["notes"].presence || person.notes,
          linkedin_url: row["linkedin_url"].presence || person.linkedin_url,
          met_on: row["met_on"].presence || person.met_on
        )
        person.save!
        person.apply_how_met!(row["how_met"]) if row["how_met"]
        # Reviewed overrides for introducer/context win over the parser
        person.update!(introducer: Introducer.for_label(row["introducer"])) if row.key?("introducer")
        person.update!(relationship_context: row["context"]) if row["context"].present?
        person.assign_companies!(Array(row["companies"]))
      end
      person
    end

    def apply_batch!(batch)
      count = 0
      batch.rows.each do |row|
        next unless ActiveModel::Type::Boolean.new.cast(row["include"])
        apply_row!(row, source: batch.format == "linkedin" ? "linkedin" : "spreadsheet")
        count += 1
      end
      batch.update!(state: "applied")
      count
    end
  end
end
