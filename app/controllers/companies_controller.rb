class CompaniesController < ApplicationController
  def index
    @companies = Company.includes(:people, :company_snapshots).order(:name)
    @new_grad_counts = JobPosting.new_grad.live.group(:company_id).count
  end

  def create
    Company.find_or_create_by_name!(params[:name]).update!(watch: true) if params[:name].present?
    redirect_to companies_path, notice: "Watching #{params[:name]}."
  end

  def update
    company = Company.find(params[:id])
    attrs = params.require(:company).permit(:industry, :ats_provider, :ats_slug, :careers_url, :website, :watch)
    attrs[:ats_verified] = true if attrs[:ats_provider].present? || attrs[:ats_slug].present?
    attrs[:ats_provider] = attrs[:ats_provider].presence if attrs.key?(:ats_provider)
    attrs[:careers_checked_at] = nil if attrs[:website].present? && attrs[:website] != company.website # re-scan new site
    company.update!(attrs)
    redirect_to companies_path, notice: "Updated #{company.name}."
  end
end
