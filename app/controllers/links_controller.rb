class LinksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :create ]
  def index
    @links = Link.all

    render json: @links
  end

  def create
    shortener = Shortener.new(link_params[:original_url])
    @link = shortener.generate_short_link

    render json: @link, status: :created
  end

  private

  def link_params
    params.require(:link).permit(:original_url)
  end
end
