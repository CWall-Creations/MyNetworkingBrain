class RefreshRun < ApplicationRecord
  def self.latest = order(:created_at).last
  def running? = started_at && finished_at.nil? && started_at > 30.minutes.ago
  def log!(line)
    update_columns(log: [log, "#{Time.current.strftime('%H:%M:%S')} #{line}"].compact.join("\n"))
  end
end
