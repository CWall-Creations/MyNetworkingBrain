class ProfilesController < ApplicationController
  def show
    @profile = Profile.current
    @fits = IndustryFit.order(score: :desc)
    @counts = Person.group(:industry).count
  end

  def update
    Profile.current.update!(params.require(:profile).permit(*Profile::EDITABLE, *Profile::LIST_FIELDS).to_h)
    redirect_to profile_path, notice: "Profile saved."
  end

  # Upload a resume, then (if the agent is connected) fill in the profile from it.
  def resume
    return redirect_to(profile_path, alert: "Choose a file first.") unless params[:resume].respond_to?(:read)
    Profile.current.attach_resume!(params[:resume])
    if Agent::Client.configured?
      filled = Agent::Tasks.profile_from_resume!
      redirect_to profile_path, notice: filled.any? ? "Resume saved. Filled in: #{filled.map(&:humanize).to_sentence}. Check it below." : "Resume saved. Your profile was already filled in."
    else
      redirect_to profile_path, notice: "Resume saved. Connect Claude below to fill in your profile from it."
    end
  rescue ArgumentError => e
    redirect_to profile_path, alert: e.message
  end

  def fill
    filled = Agent::Tasks.profile_from_resume!(overwrite: params[:overwrite] == "1")
    redirect_to profile_path, notice: filled.any? ? "Filled in: #{filled.map(&:humanize).to_sentence}." : "Nothing to fill: every field already has a value (tick “replace” to overwrite)."
  rescue ArgumentError => e
    redirect_to profile_path, alert: e.message
  end

  def api_key
    if params[:remove]
      Agent::Setup.remove_key!
      redirect_to profile_path, notice: "Claude disconnected."
    else
      Agent::Setup.save_key!(params[:api_key])
      redirect_to profile_path, notice: "Claude connected. The key is saved in .env on this computer only."
    end
  rescue Agent::Setup::InvalidKey => e
    redirect_to profile_path, alert: e.message
  end

  def analyze
    Agent::Tasks.industry_fit!
    Feed::Builder.new.run
    redirect_to profile_path, notice: "Industry fit updated."
  end
end
