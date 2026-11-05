module Jobs
  module Boards
    # Normalized posting shape every adapter returns.
    Posting = Struct.new(:external_id, :title, :url, :location, :posted_at, :description, keyword_init: true)

    # Public ATS job boards. Each adapter: .fetch(slug) => [Posting] or nil (board not found).
    module Greenhouse
      module_function

      def fetch(slug)
        data = Http.get_json("https://boards-api.greenhouse.io/v1/boards/#{slug}/jobs")
        data && parse(data)
      end

      def parse(data)
        Array(data["jobs"]).map do |j|
          Posting.new(external_id: "gh-#{j["id"]}", title: j["title"], url: j["absolute_url"],
                      location: j.dig("location", "name"),
                      posted_at: Boards.time(j["first_published"] || j["updated_at"]))
        end
      end
    end

    module Lever
      module_function

      def fetch(slug)
        data = Http.get_json("https://api.lever.co/v0/postings/#{slug}?mode=json")
        data.is_a?(Array) ? parse(data) : nil
      end

      def parse(data)
        data.map do |j|
          Posting.new(external_id: "lv-#{j["id"]}", title: j["text"], url: j["hostedUrl"],
                      location: j.dig("categories", "location"),
                      posted_at: j["createdAt"] && Time.at(j["createdAt"] / 1000),
                      description: j["descriptionPlain"])
        end
      end
    end

    module Ashby
      module_function

      def fetch(slug)
        data = Http.get_json("https://api.ashbyhq.com/posting-api/job-board/#{slug}")
        data && parse(data)
      end

      def parse(data)
        Array(data["jobs"]).map do |j|
          Posting.new(external_id: "ab-#{j["id"]}", title: j["title"], url: j["jobUrl"],
                      location: j["location"], posted_at: Boards.time(j["publishedAt"]),
                      description: j["descriptionPlain"])
        end
      end
    end

    # Workday career sites (used by many large employers). The slug is the
    # careers URL, e.g. "https://salesforce.wd12.myworkdayjobs.com/External_Career_Site".
    module Workday
      QUERIES = ["new grad", "university", "early career", "entry level", "graduate"].freeze

      module_function

      def fetch(careers_url)
        uri = URI(careers_url)
        tenant = uri.host.split(".").first
        site = uri.path.split("/").reject { |s| s.empty? || s.match?(/\A[a-z]{2}-[A-Z]{2}\z/) }.first
        return nil unless tenant && site

        api = "https://#{uri.host}/wday/cxs/#{tenant}/#{site}/jobs"
        seen = {}
        QUERIES.each do |q|
          data = Http.post_json(api, { appliedFacets: {}, limit: 20, offset: 0, searchText: q })
          return nil if data.nil? && seen.empty? && q == QUERIES.first
          Array(data&.dig("jobPostings")).each do |j|
            seen[j["externalPath"]] ||= Posting.new(
              external_id: "wd-#{j["externalPath"]}", title: j["title"],
              url: "https://#{uri.host}/#{site}#{j["externalPath"]}",
              location: j["locationsText"], posted_at: posted_on(j["postedOn"])
            )
          end
        end
        seen.values
      end

      # "Posted Today" / "Posted Yesterday" / "Posted 3 Days Ago" / "Posted 30+ Days Ago"
      def posted_on(text)
        case text.to_s
        when /today/i then Time.current
        when /yesterday/i then 1.day.ago
        when /(\d+)\+?\s*days?/i then Regexp.last_match(1).to_i.days.ago
        end
      end
    end

    module Workable
      module_function

      def fetch(slug)
        data = Http.post_json("https://apply.workable.com/api/v3/accounts/#{slug}/jobs", {})
        data.is_a?(Hash) && data["results"] ? parse(data, slug) : nil
      end

      def parse(data, slug)
        data["results"].map do |j|
          loc = j["location"].is_a?(Hash) ? [j.dig("location", "city"), j.dig("location", "country")].compact.join(", ") : nil
          Posting.new(external_id: "wk-#{j["shortcode"]}", title: j["title"], url: "https://apply.workable.com/#{slug}/j/#{j["shortcode"]}/",
                      location: loc, posted_at: Boards.time(j["published"]))
        end
      end
    end

    module SmartRecruiters
      module_function

      def fetch(slug)
        data = Http.get_json("https://api.smartrecruiters.com/v1/companies/#{slug}/postings?limit=100")
        data.is_a?(Hash) && data["content"] && data["totalFound"].to_i.positive? ? parse(data, slug) : nil
      end

      def parse(data, slug)
        data["content"].map do |j|
          Posting.new(external_id: "sr-#{j["id"]}", title: j["name"], url: "https://jobs.smartrecruiters.com/#{slug}/#{j["id"]}",
                      location: j.dig("location", "fullLocation") || j.dig("location", "city"), posted_at: Boards.time(j["releasedDate"]))
        end
      end
    end

    module Rippling
      module_function

      def fetch(slug)
        data = Http.get_json("https://ats.rippling.com/api/v2/board/#{slug}/jobs")
        data.is_a?(Hash) && data["items"] ? parse(data) : nil
      end

      def parse(data)
        data["items"].map do |j|
          loc = Array(j["locations"]).map { |l| l.is_a?(Hash) ? l["name"] : l }.compact.join("; ")
          Posting.new(external_id: "rp-#{j["id"]}", title: j["name"], url: j["url"], location: loc.presence)
        end
      end
    end

    module BambooHR
      module_function

      # A wrong guess redirects to BambooHR's marketing site (HTML), so only accept real JSON.
      def fetch(slug)
        data = Http.get_json("https://#{slug}.bamboohr.com/careers/list")
        data.is_a?(Hash) && data["result"].is_a?(Array) ? parse(data, slug) : nil
      end

      def parse(data, slug)
        data["result"].map do |j|
          loc = j["location"].is_a?(Hash) ? [j.dig("location", "city"), j.dig("location", "state")].compact.join(", ") : nil
          Posting.new(external_id: "bh-#{j["id"]}", title: j["jobOpeningName"], url: "https://#{slug}.bamboohr.com/careers/#{j["id"]}",
                      location: loc.presence)
        end
      end
    end

    # ADP Workforce Now career centers. The "slug" is "cid|ccId" from the embed on the careers page.
    module Adp
      BASE = "https://workforcenow.adp.com/mascsr/default".freeze
      module_function

      def fetch(slug)
        cid, cc = slug.to_s.split("|")
        return nil if cid.blank?
        data = Http.get_json("#{BASE}/careercenter/public/events/staffing/v1/job-requisitions?cid=#{cid}&ccId=#{cc}&lang=en_US&locale=en_US&$top=100")
        data.is_a?(Hash) && data["jobRequisitions"] ? parse(data, cid, cc) : nil
      end

      def parse(data, cid, cc)
        data["jobRequisitions"].map do |j|
          loc = Array(j["requisitionLocations"]).filter_map { |l| l.dig("nameCode", "shortName")&.strip }.first
          Posting.new(external_id: "adp-#{j["itemID"]}", title: j["requisitionTitle"], location: loc,
                      url: "#{BASE}/mdf/recruitment/recruitment.html?cid=#{cid}&ccId=#{cc}&jobId=#{j["itemID"]}&lang=en_US",
                      posted_at: Boards.time(j["postDate"]))
        end
      end
    end

    # Any careers page that embeds schema.org JobPosting data (common on company sites).
    # The "slug" is the careers page URL.
    module CareersPage
      module_function

      def fetch(url)
        html, final = Http.get_html(url)
        html && parse(html, final)
      end

      def parse(html, base_url)
        html.scan(%r{<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>}mi).flat_map do |(json)|
          data = begin
            JSON.parse(json)
          rescue JSON::ParserError
            nil
          end
          job_postings(data).map do |j|
            url = begin
              j["url"].presence && URI.join(base_url, j["url"]).to_s
            rescue URI::InvalidURIError
              j["url"]
            end
            locs = j["jobLocation"].is_a?(Hash) ? [j["jobLocation"]] : Array(j["jobLocation"])
            loc = locs.filter_map { |l| l.is_a?(Hash) ? l.dig("address", "addressLocality") : nil }.join("; ")
            Posting.new(external_id: "cp-#{Digest::SHA1.hexdigest([j["title"], url].join)[0, 16]}", title: j["title"],
                        url: url || base_url, location: loc.presence, posted_at: Boards.time(j["datePosted"]),
                        description: j["description"].to_s.gsub(/<[^>]+>/, " ")[0, 3000])
          end
        end.select { |p| p.title.present? }.uniq(&:external_id)
      end

      def job_postings(data)
        case data
        when Array then data.flat_map { |d| job_postings(d) }
        when Hash
          return [data] if Array(data["@type"]).include?("JobPosting")
          job_postings(data["@graph"] || data["itemListElement"]&.map { |i| i["item"] || i } || [])
        else []
        end
      end
    end

    PROVIDERS = { "greenhouse" => Greenhouse, "lever" => Lever, "ashby" => Ashby, "workday" => Workday,
                  "workable" => Workable, "smartrecruiters" => SmartRecruiters, "rippling" => Rippling,
                  "bamboohr" => BambooHR, "adp" => Adp, "careers_page" => CareersPage }.freeze

    def self.time(value)
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
