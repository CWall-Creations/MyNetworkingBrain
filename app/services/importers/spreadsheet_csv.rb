require "csv"

module Importers
  # Any spreadsheet CSV. Column headers are mapped via `spreadsheet_columns`
  # in data/profile.yml, so template users keep their own headers.
  class SpreadsheetCsv
    def initialize(io_or_string, columns: Profile.current.spreadsheet_columns)
      @csv = io_or_string.respond_to?(:read) ? io_or_string.read : io_or_string.to_s
      @columns = columns
    end

    def rows
      table = CSV.parse(@csv.sub(/\A﻿/, ""), headers: true)
      table.filter_map do |r|
        get = ->(field) { (h = @columns[field]) && r[h]&.strip }
        name = get.("name")
        next if name.blank?
        Row.build(name:, position: get.("position"), company: get.("company"),
                  industry_tags: get.("industry_tags"), how_met: get.("how_met"),
                  closeness: get.("closeness"), notes: get.("notes"))
      end
    end
  end
end
