class Introducer < ApplicationRecord
  belongs_to :person, optional: true   # e.g. the "Uncle" hub is also a contact
  has_many :people, dependent: :nullify
  validates :label, presence: true, uniqueness: { case_sensitive: false }

  def self.for_label(label)
    return nil if label.blank?
    where("lower(label) = ?", label.downcase).first || create!(label: label)
  end
end
