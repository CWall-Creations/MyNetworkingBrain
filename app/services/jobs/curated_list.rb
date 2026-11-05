module Jobs
  # Community-maintained new-grad lists (configured in config/job_sources.yml).
  # Downloads are cached in tmp/cache for a few hours (the SimplifyJobs file is ~13MB).
  class CuratedList
    CACHE_TTL = 6.hours

    def self.sources
      YAML.load_file(Rails.root.join("config/job_sources.yml")).fetch("curated_lists", [])
    end

    # Returns { normalized_company_name => [Posting] } for active listings.
    def self.by_company
      sources.each_with_object(Hash.new { |h, k| h[k] = [] }) do |src, acc|
        Array(load(src)).each do |j|
          next unless j["active"] != false && j["is_visible"] != false
          acc[Company.normalize(j["company_name"])] << Boards::Posting.new(
            external_id: "cl-#{j["id"]}", title: j["title"], url: j["url"],
            location: Array(j["locations"]).join("; "),
            posted_at: j["date_posted"] && Time.at(j["date_posted"].to_i)
          )
        end
      end
    end

    def self.load(src)
      path = Rails.root.join("tmp/cache/curated_#{src["name"].parameterize}.json")
      if !File.exist?(path) || File.mtime(path) < CACHE_TTL.ago
        data = Http.get_json(src["url"], timeout: 30)
        return nil unless data
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate(data))
        return data
      end
      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end
  end
end
