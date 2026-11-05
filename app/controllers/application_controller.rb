class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  rescue_from Agent::Client::NotConfigured, Agent::Client::Refused do |e|
    redirect_back fallback_location: root_path, alert: e.message
  end

  rescue_from Anthropic::Errors::APIError do |e|
    redirect_back fallback_location: root_path, alert: "Claude API error: #{e.message.truncate(160)}"
  end

  private

  # Daily auto-refresh while the app is open (local-only: nothing runs when it's closed).
  def auto_refresh
    last = RefreshRun.latest
    return if last&.running? || (last&.finished_at && last.finished_at > 24.hours.ago)
    return if Person.none?
    RefreshNetworkJob.perform_later(RefreshRun.create!.id)
  end
end
