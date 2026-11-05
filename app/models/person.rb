class Person < ApplicationRecord
  STATUSES = %w[employed retired self_employed student unemployed].freeze
  SOURCES = %w[form yaml spreadsheet linkedin agent].freeze

  belongs_to :introducer, optional: true
  has_many :affiliations, dependent: :destroy
  has_many :companies, through: :affiliations
  has_many :interactions, -> { order(occurred_on: :desc) }, dependent: :destroy
  has_many :feed_items, dependent: :destroy
  has_one :hub, class_name: "Introducer", dependent: :nullify  # if this person is also a hub

  validates :name, presence: true
  validates :closeness, inclusion: { in: 1..5 }
  validates :status, inclusion: { in: STATUSES }

  def primary_company
    affiliations.find(&:primary)&.company || companies.first
  end

  def company_names = companies.map(&:name).join(" & ")

  def last_contact
    [interactions.maximum(:occurred_on), last_contact_on].compact.max
  end

  def strength(today: Date.current)
    StrengthScore.new(half_life_days: Profile.current.half_life_days, today:).call(
      closeness:, last_contact_on: last_contact,
      recent_interactions: interactions.where("occurred_on >= ?", today - StrengthScore::RECENT_BONUS_DAYS).count
    )
  end

  def strength_label = StrengthScore.label(strength)
  def job_seeking_relevant? = status == "employed"

  def how_met_summary
    return how_met if how_met.present?
    [relationship_context, introducer && "via #{introducer.label}"].compact.join(", ")
  end

  # Replaces company links from a list of names; first one is primary.
  def assign_companies!(names)
    names = Array(names).map(&:strip).reject(&:blank?).uniq
    ids = names.map do |n|
      company = Company.find_or_create_by_name!(n)
      company.update!(industry:) if company.industry.blank? && industry.present? && industry != "Other"
      company.id
    end
    affiliations.where.not(company_id: ids).destroy_all
    ids.each_with_index do |cid, i|
      aff = affiliations.find_or_initialize_by(company_id: cid)
      aff.update!(primary: i.zero?, current: true)
    end
    affiliations.reset
  end

  # Applies a parsed "how we met" string: sets context, introducer hub, or
  # links this person as a hub (how_met == "Uncle" => this person IS "Uncle").
  def apply_how_met!(text)
    parsed = HowMetParser.parse(text)
    self.how_met = text
    self.relationship_context = parsed.context
    self.introducer = Introducer.for_label(parsed.introducer)
    save!
    Introducer.for_label(parsed.self_label).update!(person: self) if parsed.self_label
    parsed
  end
end
