class InteractionsController < ApplicationController
  def create
    person = Person.find(params[:person_id])
    person.interactions.create!(params.require(:interaction).permit(:occurred_on, :kind, :notes))
    redirect_to person_path(person)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to person_path(person), alert: e.message
  end

  def destroy
    person = Person.find(params[:person_id])
    person.interactions.find(params[:id]).destroy!
    redirect_to person_path(person)
  end
end
