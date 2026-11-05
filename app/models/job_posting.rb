class JobPosting < ApplicationRecord
  belongs_to :company
  scope :new_grad, -> { where(new_grad: true) }
  scope :live, -> { where("last_seen_at > ?", 3.days.ago) }
end
