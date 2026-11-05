class PeopleController < ApplicationController
  before_action :set_person, only: %i[show edit update destroy draft]

  def index
    @people = Person.includes(:companies, :introducer, :interactions).order(:name)
    respond_to do |f|
      f.html
      f.csv { send_data Exporters::Csv.generate(@people), filename: "network-#{Date.current}.csv" }
    end
  end

  def show
    @jobs = JobPosting.new_grad.live.where(company: @person.companies).order(posted_at: :desc).limit(5)
  end

  def new
    @person = Person.new(closeness: Profile.current.default_closeness)
  end

  def edit; end

  def create
    @person = Person.new(source: "form")
    save_person(:new)
  end

  def update = save_person(:edit)

  def destroy
    @person.destroy!
    redirect_to people_path, notice: "Removed #{@person.name}."
  end

  # Bulk closeness rating from the People table.
  def rate
    params.fetch(:closeness, {}).each { |id, v| Person.find_by(id:)&.update(closeness: v.to_i.clamp(1, 5)) }
    redirect_to people_path, notice: "Ratings saved."
  end

  # "Describe someone" -> Claude fills in the form. Only the description is sent.
  def intake
    out = Agent::Tasks.intake(params[:description].to_s)
    @person = Person.new(name: params[:name], position: out["position"], how_met: out["how_met"],
                         industry_tags: out["industry_tags"], notes: out["notes"].presence,
                         closeness: out["closeness"].to_i.clamp(1, 5).nonzero? || 3,
                         industry: IndustryClassifier.classify(out["industry_tags"], out["position"]))
    @companies_text = out["company"]
    flash.now[:notice] = "Review what the agent filled in, then save."
    render :new
  end

  def draft
    @draft = Agent::Tasks.draft_message(@person, reason: params[:reason])
    @jobs = JobPosting.new_grad.live.where(company: @person.companies).order(posted_at: :desc).limit(5)
    render :show
  end

  private

  def set_person = @person = Person.find(params[:id])

  def save_person(template)
    attrs = params.require(:person).permit(:name, :position, :status, :industry, :closeness, :notes,
                                           :met_on, :last_contact_on, :linkedin_url)
    attrs[:industry_tags] = params[:person][:industry_tags].to_s.split(",").map(&:strip).reject(&:empty?)
    how_met = params[:person][:how_met]
    Person.transaction do
      @person.update!(attrs)
      @person.apply_how_met!(how_met) if how_met != @person.how_met || @person.how_met.nil?
      @person.update!(industry: IndustryClassifier.classify(@person.industry_tags, @person.position)) if @person.industry.blank?
      @person.assign_companies!(params[:person][:companies].to_s.split(/\s*(?:&|,)\s*/))
    end
    redirect_to people_path, notice: "Saved #{@person.name}."
  rescue ActiveRecord::RecordInvalid
    @companies_text = params[:person][:companies]
    render template, status: :unprocessable_entity
  end
end
