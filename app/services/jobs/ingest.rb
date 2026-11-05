module Jobs
  # Pulls postings for every tracked company, flags new grad roles, records a
  # daily snapshot (for hiring trends) and merges curated new-grad lists.
  class Ingest
    ATS_RECHECK = 14.days

    def initialize(log: ->(_) {}) = @log = log

    def run
      curated = safe { CuratedList.by_company } || {}
      Company.tracked.find_each do |company|
        next if skip?(company)
        postings = fetch_board(company)
        curated_hits = curated[company.normalized_name] || []
        Array(postings).each { |p| self.class.upsert_posting(company, p, source: company.ats_provider) }
        curated_hits.each { |p| self.class.upsert_posting(company, p, source: "curated", force_new_grad: true) }
        snapshot(company, postings) if postings
        @log.call("#{company.name}: #{postings ? "#{postings.size} open" : 'no public board'}" \
                  "#{", #{curated_hits.size} curated new-grad" if curated_hits.any?}")
      end
    end

    def self.upsert_posting(company, p, source:, force_new_grad: false)
      job = company.job_postings.find_or_initialize_by(external_id: p.external_id)
      job.assign_attributes(title: p.title.to_s.truncate(250), url: p.url, location: p.location&.truncate(250),
                            source:, posted_at: p.posted_at || job.posted_at,
                            new_grad: force_new_grad || NewGradFilter.new_grad?(p.title, p.description),
                            first_seen_at: job.first_seen_at || Time.current, last_seen_at: Time.current)
      job.save!
      job
    end

    private

    # Companies that clearly aren't employers to search (e.g. your "Retired" placeholder)
    def skip?(company)
      company.ats_provider == "none" && company.careers_url.blank? &&
        company.ats_checked_at && company.ats_checked_at > ATS_RECHECK.ago &&
        company.careers_checked_at && company.careers_checked_at > ATS_RECHECK.ago
    end

    def fetch_board(company)
      discover_careers(company)
      if company.ats_provider.present? && company.ats_provider != "none"
        return Boards::PROVIDERS[company.ats_provider]&.fetch(company.ats_slug)
      end
      unless company.ats_checked_at && company.ats_checked_at > ATS_RECHECK.ago
        provider, slug, postings = AtsDetector.detect(company.name)
        company.update!(ats_provider: provider || "none", ats_slug: slug, ats_checked_at: Time.current, ats_verified: false)
        return postings if provider
      end
      # Last resort: job listings embedded in the careers page itself
      company.careers_url.present? ? Boards::CareersPage.fetch(company.careers_url).presence : nil
    end

    # Finds the careers page (and its job system) from the company's own website.
    def discover_careers(company)
      return if company.careers_checked_at && company.careers_checked_at > ATS_RECHECK.ago
      company.website = CareersFinder.guess_website(company.name) if company.website.blank?
      result = company.website.present? ? CareersFinder.call(company.website) : nil
      attrs = { careers_checked_at: Time.current, website: company.website }
      if result
        attrs[:careers_url] = result.careers_url if company.careers_url.blank?
        # A job system linked from their own site beats a guessed slug, unless you set one yourself
        if result.provider && (company.ats_provider.blank? || company.ats_provider == "none" || !company.ats_verified)
          attrs.merge!(ats_provider: result.provider, ats_slug: result.slug, ats_verified: true, ats_checked_at: Time.current)
        end
        @log.call("#{company.name}: careers page found#{" (#{result.provider})" if result.provider}")
      end
      company.update!(attrs)
    rescue StandardError => e
      @log.call("#{company.name}: careers lookup failed (#{e.class})")
    end

    def snapshot(company, postings)
      snap = company.company_snapshots.find_or_initialize_by(taken_on: Date.current)
      snap.update!(open_count: postings.size,
                   new_grad_count: postings.count { |p| NewGradFilter.new_grad?(p.title, p.description) })
    end

    def safe
      yield
    rescue StandardError => e
      @log.call("curated lists unavailable: #{e.message}")
      nil
    end
  end
end
