module Jobs
  # Finds a company's careers page from its website, and which job system
  # (Greenhouse, Lever, Workday, ...) that page links to.
  #
  #   1. Look for a "Careers" / "Jobs" / "Join us" link on the homepage.
  #   2. Otherwise try common paths (/careers, /jobs, careers.example.com, ...).
  #   3. Scan that page for links into a known job system.
  #
  # A job system found this way is trusted (it came from the company's own site),
  # unlike a guessed board slug.
  class CareersFinder
    Result = Struct.new(:careers_url, :provider, :slug, keyword_init: true)

    LINK_TEXT = /\b(careers?|jobs|join (us|our team|the team)|work (with|at) us|open (roles|positions)|we'?re hiring)\b/i
    PATHS = %w[/careers /careers/ /jobs /company/careers /about/careers /about-us/careers /join-us /join /work-with-us].freeze

    ATS_PATTERNS = [
      ["greenhouse", %r{(?:boards|job-boards)(?:\.eu)?\.greenhouse\.io/(?:embed/job_board\?for=)?([a-z0-9_-]+)}i],
      ["greenhouse", %r{boards-api\.greenhouse\.io/v1/boards/([a-z0-9_-]+)}i],
      ["lever", %r{jobs\.lever\.co/([a-z0-9_.-]+)}i],
      ["ashby", %r{jobs\.ashbyhq\.com/([a-z0-9_.%-]+)}i],
      ["workable", %r{apply\.workable\.com/([a-z0-9_-]+)}i],
      ["smartrecruiters", %r{(?:jobs|careers)\.smartrecruiters\.com/([a-z0-9_-]+)}i],
      ["rippling", %r{ats\.rippling\.com/([a-z0-9_-]+)}i],
      ["bamboohr", %r{([a-z0-9-]+)\.bamboohr\.com}i],
      ["workday", %r{(https://[a-z0-9-]+\.wd\d+\.myworkdayjobs\.com/(?:[a-z]{2}-[A-Z]{2}/)?[A-Za-z0-9_-]+)}]
    ].freeze
    IGNORED_SLUGS = %w[embed js api www careers jobs v1 boards static].freeze

    def self.call(website) = new(website).call

    # Best-effort website guess for a company with none: name.com / .ai / .io,
    # accepted only if the page title mentions the company's name.
    def self.guess_website(name)
      words = name.to_s.downcase.scan(/[a-z0-9]+/) - %w[inc llc corp corporation co the]
      return nil if words.empty?
      base = words.join
      %w[com ai io co].each do |tld|
        html, final = Http.get_html("https://#{base}.#{tld}", timeout: 8)
        next unless html
        title = html[/<title[^>]*>([^<]*)/i, 1].to_s.downcase
        return URI(final).then { |u| "#{u.scheme}://#{u.host}" } if title.include?(words.first) && !title.match?(/for sale|domain|parked/)
      end
      nil
    end

    def initialize(website)
      @website = normalize(website)
    end

    def call
      return nil unless @website
      home, home_url = Http.get_html(@website)
      # Some homepages link straight to the job system
      if home && (ats = detect_ats(home))
        page = careers_link(home, home_url) || ats_url(*ats)
        return Result.new(careers_url: page, provider: ats[0], slug: ats[1])
      end

      candidates = [home && careers_link(home, home_url)].compact + guessed_urls
      candidates.uniq.each do |url|
        html, final = Http.get_html(url)
        next unless html && careers_page?(html, final)
        provider, slug = detect_ats(html)
        provider, slug = "careers_page", final if provider.nil? && Boards::CareersPage.parse(html, final).any?
        return Result.new(careers_url: final, provider:, slug:)
      end
      nil
    end

    def detect_ats(html)
      # ADP Workforce Now embeds: cid='...' ccid='...' (or ?cid=...&ccId=... in a link)
      if html.include?("workforcenow.adp.com") &&
         (cid = html[/\bcid=['"]?([0-9a-f-]{36})/i, 1]) && (cc = html[/\bccid=['"]?([0-9_]+)/i, 1])
        return ["adp", "#{cid}|#{cc}"]
      end
      ATS_PATTERNS.each do |provider, re|
        html.scan(re).flatten.each do |slug|
          next if slug.blank? || IGNORED_SLUGS.include?(slug.downcase)
          return [provider, slug.delete_suffix("/")]
        end
      end
      nil
    end

    private

    def normalize(site)
      s = site.to_s.strip
      return nil if s.empty?
      s = "https://#{s}" unless s.match?(%r{\Ahttps?://})
      URI(s).then { |u| "#{u.scheme}://#{u.host}" }
    rescue URI::InvalidURIError
      nil
    end

    def careers_link(html, base)
      html.scan(%r{<a\b[^>]*href=["']([^"'#]+)["'][^>]*>(.*?)</a>}mi).each do |href, text|
        label = text.gsub(/<[^>]+>/, " ").squeeze(" ").strip
        next unless label.match?(LINK_TEXT) || href.match?(%r{/(careers?|jobs)(/|\z|\?)}i)
        next if href.start_with?("mailto:", "tel:", "javascript:")
        return URI.join(base, href).to_s
      rescue URI::InvalidURIError
        next
      end
      nil
    end

    def guessed_urls
      host = URI(@website).host.delete_prefix("www.")
      PATHS.map { |p| "#{@website}#{p}" } + ["https://careers.#{host}", "https://jobs.#{host}"]
    end

    def careers_page?(html, url)
      url.match?(/career|job|join|hiring/i) || html[0, 20_000].match?(/<title[^>]*>[^<]*(career|job|join)/i)
    end

    def ats_url(provider, slug)
      { "greenhouse" => "https://boards.greenhouse.io/#{slug}", "lever" => "https://jobs.lever.co/#{slug}",
        "ashby" => "https://jobs.ashbyhq.com/#{slug}", "workable" => "https://apply.workable.com/#{slug}/",
        "smartrecruiters" => "https://jobs.smartrecruiters.com/#{slug}", "rippling" => "https://ats.rippling.com/#{slug}/jobs",
        "bamboohr" => "https://#{slug}.bamboohr.com/careers", "workday" => slug }[provider]
    end
  end
end
