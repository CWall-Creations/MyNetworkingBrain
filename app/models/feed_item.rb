class FeedItem < ApplicationRecord
  belongs_to :person, optional: true
  belongs_to :company, optional: true
  belongs_to :job_posting, optional: true
  scope :open, -> { where(state: "open") }
  CAPS = { "job_match" => 3, "reach_out" => 3, "trend" => 1, "industry_fit" => 1 }.freeze

  # Best items overall, but capped per kind so one kind never floods the feed.
  def self.top(n = 7)
    taken = Hash.new(0)
    open.order(score: :desc).includes(:person, :company).each_with_object([]) do |item, out|
      next if taken[item.kind] >= CAPS.fetch(item.kind, 2)
      taken[item.kind] += 1
      out << item
      break out if out.size >= n
    end
  end
end
