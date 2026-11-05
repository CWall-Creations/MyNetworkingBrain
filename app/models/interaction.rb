class Interaction < ApplicationRecord
  KINDS = %w[coffee_chat call message email event referral other].freeze
  belongs_to :person, touch: true
  validates :occurred_on, presence: true
  validates :kind, inclusion: { in: KINDS }
end
