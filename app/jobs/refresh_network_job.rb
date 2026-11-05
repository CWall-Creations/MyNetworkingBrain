# Full refresh: job boards -> snapshots -> AI classification/news -> feed.
# Triggered by the Refresh button, and automatically once a day when you open the app.
class RefreshNetworkJob < ApplicationJob
  queue_as :default
  NEWS_PER_RUN = 6
  NEWS_TTL = 7.days

  def perform(run_id = nil)
    run = RefreshRun.find_by(id: run_id) || RefreshRun.create!
    run.update!(started_at: Time.current, finished_at: nil, log: nil)
    log = ->(line) { run.log!(line) }

    step(log, "job boards") { Jobs::Ingest.new(log:).run }

    if Agent::Client.configured?
      @agent_ok = true
      unclassified = Person.where(industry: [nil, "", "Other"]).includes(:companies).to_a
      agent_step(log, "classify #{unclassified.size}") { Agent::Tasks.classify!(unclassified) } if unclassified.any?
      agent_step(log, "industry fit") { Agent::Tasks.industry_fit! } if IndustryFit.none? || IndustryFit.maximum(:updated_at) < 30.days.ago
      news_targets.each { |c| agent_step(log, "news: #{c.name}") { Agent::Tasks.hiring_news!(c) } }
    else
      log.("agent skipped (no ANTHROPIC_API_KEY): using offline industry keywords")
      Person.where(industry: [nil, ""]).find_each do |p|
        p.update!(industry: IndustryClassifier.classify(p.industry_tags, p.position, p.company_names))
      end
    end

    step(log, "feed") { Feed::Builder.new.run }
  ensure
    run&.update!(finished_at: Time.current)
  end

  private

  # Like step, but stops all further AI steps if the API account has no credit.
  def agent_step(log, name, &block)
    return unless @agent_ok
    yield
    log.("✓ #{name}")
  rescue Anthropic::Errors::APIStatusError => e
    if e.message.match?(/credit balance|billing/i)
      @agent_ok = false
      log.("⏸ agent paused: your Anthropic API account has no credit (console.anthropic.com → Plans & Billing)")
    else
      log.("✗ #{name}: #{e.message.truncate(200)}")
    end
  rescue StandardError => e
    log.("✗ #{name}: #{e.class}: #{e.message.truncate(200)}")
  end

  def step(log, name)
    t = Time.current
    yield
    log.("✓ #{name} (#{(Time.current - t).round(1)}s)")
  rescue StandardError => e
    log.("✗ #{name}: #{e.class}: #{e.message.truncate(200)}")
    Rails.logger.error(e.full_message)
  end

  # Prioritize companies in your focus industries / with closer contacts.
  def news_targets
    focus = Profile.current.focus_industries
    Company.tracked.where("news_checked_at IS NULL OR news_checked_at < ?", NEWS_TTL.ago)
           .includes(:people).to_a
           .reject { |c| c.people.none?(&:job_seeking_relevant?) && !c.watch }
           .sort_by { |c| -(c.people.map(&:closeness).max.to_i + (focus.include?(c.industry) ? 3 : 0)) }
           .first(NEWS_PER_RUN)
  end
end
