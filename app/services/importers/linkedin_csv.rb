require "csv"

module Importers
  # LinkedIn "Connections.csv" (Settings > Data privacy > Get a copy of your data).
  # The file starts with a few "Notes:" lines before the real header row.
  class LinkedinCsv
    HEADER = /^First Name,Last Name/

    def self.linkedin?(text) = text.to_s.lines.first(10).any? { |l| l.match?(HEADER) }

    def initialize(io_or_string)
      @csv = io_or_string.respond_to?(:read) ? io_or_string.read : io_or_string.to_s
    end

    def rows
      lines = @csv.sub(/\A﻿/, "").lines
      start = lines.index { |l| l.match?(HEADER) } or return []
      CSV.parse(lines[start..].join, headers: true).filter_map do |r|
        name = [r["First Name"], r["Last Name"]].compact.join(" ").strip
        next if name.empty?
        Row.build(name:, position: r["Position"], company: r["Company"], how_met: "LinkedIn",
                  linkedin_url: r["URL"], met_on: parse_date(r["Connected On"]))
      end
    end

    private

    def parse_date(s) = s.present? ? (Date.parse(s) rescue nil) : nil
  end
end
