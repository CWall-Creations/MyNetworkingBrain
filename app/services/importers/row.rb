module Importers
  # One person as parsed from any import source, before you approve it.
  # Stored as a plain hash in ImportBatch#rows so the review screen can edit it.
  module Row
    FIELDS = %w[name position companies status industry industry_tags how_met introducer
                context closeness notes linkedin_url met_on include existing_id warnings].freeze

    module_function

    def build(name:, position: nil, company: nil, industry_tags: nil, how_met: nil,
              closeness: nil, notes: nil, linkedin_url: nil, met_on: nil)
      company_parse = CompanyParser.parse(company, position:)
      how = HowMetParser.parse(how_met)
      tags = Array(industry_tags.is_a?(String) ? industry_tags.split(/\s*,\s*/) : industry_tags).map(&:strip).reject(&:empty?)
      warnings = []
      warnings << "partial name" if name.to_s.split.size < 2 || name.to_s.include?("(")
      warnings << "no company" if company_parse.companies.empty? && company_parse.status == "employed"

      {
        "name" => name.to_s.strip,
        "position" => position.to_s.strip.presence,
        "companies" => company_parse.companies,
        "status" => company_parse.status,
        "industry" => IndustryClassifier.classify(tags, position, company),
        "industry_tags" => tags,
        "how_met" => how_met.to_s.strip.presence,
        "introducer" => how.introducer,
        "context" => how.context,
        "closeness" => (closeness.presence || Profile.current.default_closeness).to_i.clamp(1, 5),
        "notes" => notes.to_s.strip.presence,
        "linkedin_url" => linkedin_url.presence,
        "met_on" => met_on.presence&.to_s,
        "include" => true,
        "existing_id" => Applier.match(name, company_parse.companies)&.id,
        "warnings" => warnings
      }
    end
  end
end
