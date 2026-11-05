class FeedItemsController < ApplicationController
  def update
    item = FeedItem.find(params[:id])
    item.update!(state: params[:state]) if %w[done dismissed open].include?(params[:state])
    redirect_to root_path
  end
end
