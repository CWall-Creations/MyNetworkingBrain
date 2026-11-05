class GraphController < ApplicationController
  before_action :auto_refresh, only: :show

  def show
    @feed = FeedItem.top
    @run = RefreshRun.latest
  end

  def data
    render json: GraphData.new.to_h
  end
end
