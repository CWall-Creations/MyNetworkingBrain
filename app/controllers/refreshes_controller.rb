class RefreshesController < ApplicationController
  def create
    run = RefreshRun.latest
    unless run&.running?
      run = RefreshRun.create!(started_at: Time.current)
      RefreshNetworkJob.perform_later(run.id)
    end
    redirect_to root_path, notice: "Refreshing… job boards and news take a minute or two."
  end

  def show
    @run = RefreshRun.latest
    render partial: "refreshes/status", locals: { run: @run }
  end
end
