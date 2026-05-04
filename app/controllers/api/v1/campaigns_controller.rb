module Api
  module V1
    class CampaignsController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token
      before_action :set_campaign, only: %i[show update destroy pause resume]

      # GET /api/v1/campaigns
      def index
        @campaigns = current_user.link_campaigns
          .includes(:links)
          .order(created_at: :desc)

        render json: {
          campaigns: @campaigns.map { |c| serialize_campaign(c, include_links: true) }
        }
      end

      # GET /api/v1/campaigns/:id
      def show
        render json: serialize_campaign(@campaign, include_links: true)
      end

      # POST /api/v1/campaigns
      def create
        if current_user.plan.campaigns_limit_exceeded?(current_user)
          return render json: {
            error: "Campaign limit reached for #{current_user.plan.name} plan. Maximum allowed: #{current_user.plan.campaigns}."
          }, status: :too_many_requests
        end

        @campaign = current_user.link_campaigns.build(campaign_params)

        if @campaign.save
          render json: serialize_campaign(@campaign), status: :created
        else
          render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/campaigns/:id
      def update
        if @campaign.update(campaign_params)
          render json: serialize_campaign(@campaign)
        else
          render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_content
        end
      end

      # DELETE /api/v1/campaigns/:id
      def destroy
        if @campaign.default?
          return render json: { error: "The default campaign cannot be deleted." }, status: :unprocessable_entity
        end

        @campaign.destroy!
        head :no_content
      end

      # POST /api/v1/campaigns/:id/pause
      def pause
        @campaign.pause_all!(user: current_user, reason: params[:reason])
        render json: { message: "Campaign paused", state: @campaign.state }
      end

      # POST /api/v1/campaigns/:id/resume
      def resume
        @campaign.resume_all!(user: current_user, reason: params[:reason])
        render json: { message: "Campaign resumed", state: @campaign.state }
      end

      private

      def set_campaign
        @campaign = current_user.link_campaigns.includes(:links).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Campaign not found" }, status: :not_found
      end

      def campaign_params
        # :default is intentionally excluded — the default flag cannot be changed via the API
        params.require(:campaign).permit(:name, :description, :state, :accent_color)
      end

      def serialize_campaign(campaign, include_links: false)
        links_count  = campaign.links.size
        total_clicks = campaign.links.sum(&:clicks_count)

        data = {
          id:           campaign.id,
          name:         campaign.name,
          description:  campaign.description,
          state:        campaign.state,
          accent_color: campaign.accent_color,
          default:      campaign.default,
          links_count:  links_count,
          total_clicks: total_clicks,
          created_at:   campaign.created_at,
          updated_at:   campaign.updated_at
        }

        if include_links
          data[:links] = campaign.links.map { |l|
            {
              id:           l.id,
              lookup_code:  l.lookup_code,
              original_url: l.original_url,
              title:        l.title,
              state:        l.state,
              clicks_count: l.clicks_count
            }
          }
        end

        data
      end
    end
  end
end
