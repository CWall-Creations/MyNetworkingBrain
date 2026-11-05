class Company < ApplicationRecord
  has_many :affiliations, dependent: :destroy
  has_many :people, through: :affiliations
  has_many :job_postings, dependent: :destroy
  has_many :company_snapshots, dependent: :destroy

  before_validation { self.normalized_name = self.class.normalize(name) }
  validates :name, :normalized_name, presence: true

  scope :tracked, -> { where(id: Affiliation.where(current: true).select(:company_id)).or(where(watch: true)) }

  def self.normalize(name)
    name.to_s.downcase.gsub(/\b(inc|llc|corp|corporation|co|ltd)\b\.?/, "").gsub(/[^a-z0-9]/, "")
  end

  def self.find_or_create_by_name!(name)
    find_by(normalized_name: normalize(name)) || create!(name: name.strip)
  end

  def open_new_grad = job_postings.where(new_grad: true).where("last_seen_at > ?", 3.days.ago)

  # Distinct new-grad roles that match your target roles (same title in 5 cities counts once).
  def relevant_new_grad(profile = Profile.current)
    open_new_grad.order(posted_at: :desc).to_a.select { |j| profile.role_match?(j.title) }.uniq(&:title)
  end

  # Change in total openings vs. ~30 days ago (nil if not enough history).
  def hiring_trend
    snaps = company_snapshots.order(:taken_on)
    latest = snaps.last or return nil
    past = snaps.where("taken_on <= ?", latest.taken_on - 21).last or return nil
    return nil if past.open_count.zero?
    ((latest.open_count - past.open_count) / past.open_count.to_f).round(2)
  end

  def hiring? = open_new_grad.exists?
end
