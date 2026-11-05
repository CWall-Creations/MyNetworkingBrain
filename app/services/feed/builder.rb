module Feed
  # Rebuilds the ranked feed. Items keep a stable `key`, so anything you mark
  # done/dismissed stays that way across refreshes.
  class Builder
    LIMIT = 7
    JOB_FRESH_DAYS = 21

    def initialize(today: Date.current) = @today = today

    def run
      now = Time.current
      job_matches.each { |attrs| upsert(attrs, now) }
      Timing::ReachOutAdvisor.new(today: @today).nudges.first(10).each do |n|
        upsert({ key: "reach:#{n.person.id}:#{@today.strftime('%Y-%m')}", kind: "reach_out", score: n.score,
                 headline: "Reach out to #{n.person.name}", reason: n.reason, person: n.person,
                 company: n.person.primary_company }, now)
      end
      trends.each { |attrs| upsert(attrs, now) }
      fit_gap.each { |attrs| upsert(attrs, now) }
      # Anything not regenerated this run is stale
      FeedItem.open.where("refreshed_at < ? OR refreshed_at IS NULL", now).delete_all
    end

    private

    def upsert(attrs, now)
      item = FeedItem.find_or_initialize_by(key: attrs[:key])
      return if item.persisted? && item.state != "open"
      item.update!(attrs.merge(refreshed_at: now))
    end

    # One item per company with relevant new-grad roles, scored by
    # strength of your best contact x industry fit x freshness.
    def job_matches
      Company.where(id: JobPosting.new_grad.live.select(:company_id))
             .includes(affiliations: :person).filter_map do |company|
        jobs = company.relevant_new_grad
        job = jobs.first or next
        contacts = company.affiliations.select(&:current).map(&:person).select(&:job_seeking_relevant?)
        best = contacts.max_by(&:strength)
        strength = best ? best.strength : 0.15 # watched company, no contact yet
        fit = IndustryFit.score_for(company.industry || best&.industry) || 0.5
        age = job.posted_at ? (@today - job.posted_at.to_date).to_i : 7
        next if age > 60
        fresh = 0.5**(age / JOB_FRESH_DAYS.to_f)
        { key: "job:#{company.id}:#{job.id}", kind: "job_match", score: (strength * 0.5 + fit * 0.3 + fresh * 0.2).round(3),
          headline: "#{job.title} — #{company.name}",
          reason: [jobs.size > 1 && "+#{jobs.size - 1} more", best && "via #{best.name} (#{best.strength_label})",
                   age.zero? ? "posted today" : "posted #{age}d ago"].select(&:itself).join(" · "),
          url: job.url, company:, job_posting: job, person: best }
      end
    end

    def trends
      Company.tracked.filter_map do |c|
        t = c.hiring_trend or next
        next unless t.abs >= 0.2
        { key: "trend:#{c.id}:#{@today.strftime('%Y-%W')}", kind: "trend", score: 0.3 + [t.abs, 0.5].min * 0.4,
          headline: "#{c.name} openings #{t.positive? ? 'up' : 'down'} #{(t.abs * 100).round}%",
          reason: t.positive? ? "Hiring momentum: a good window to reconnect with your contacts there" :
                                "Slowing: maybe focus elsewhere for now",
          company: c }
      end
    end

    # Your best-fit industry where you have few contacts = a networking gap.
    def fit_gap
      counts = Person.group(:industry).count
      IndustryFit.order(score: :desc).limit(3).filter_map do |f|
        n = counts[f.industry].to_i
        next if n >= 3
        { key: "fit:#{f.industry}:#{@today.strftime('%Y-%m')}", kind: "industry_fit", score: (f.score * 0.6).round(3),
          headline: "Grow your #{f.industry} network",
          reason: "Strong fit (#{(f.score * 100).round}%), but only #{n} contact#{'s' unless n == 1} there. #{f.reason}".truncate(200) }
      end
    end
  end
end
