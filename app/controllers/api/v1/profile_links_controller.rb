module Api
  module V1
    # Owner curation of which governed Links appear on the profile, and their
    # order / pin / visibility / display overrides.
    class ProfileLinksController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token

      # GET /api/v1/profile/links
      # Curated links (ordered) + the owner's other links available to add.
      def index
        load_links
        render :index, status: :ok
      end

      # PATCH /api/v1/profile/links
      # Bulk "set the curation": body { links: [{ link_id, position, pinned,
      # visible, title_override, tag }] }. Links omitted from the payload are
      # removed from the profile. Any number of links may be pinned; pinned links
      # float to the top (see Profile#public_profile_links).
      def update
        profile = current_profile
        items = Array(params[:links])

        ActiveRecord::Base.transaction do
          kept_link_ids = []

          items.each_with_index do |raw, idx|
            attrs = raw.permit(:link_id, :position, :pinned, :visible, :title_override, :tag)
            link = profile.user.links.find_by(id: attrs[:link_id])
            next if link.nil?

            profile_link = profile.profile_links.find_or_initialize_by(link_id: link.id)
            profile_link.assign_attributes(
              position: attrs[:position].presence || idx,
              pinned: bool(attrs[:pinned]),
              visible: attrs.key?(:visible) ? bool(attrs[:visible]) : true,
              title_override: attrs[:title_override].presence,
              tag: attrs[:tag].presence
            )
            profile_link.save!
            kept_link_ids << link.id
          end

          profile.profile_links.where.not(link_id: kept_link_ids).destroy_all
        end

        load_links
        render :index, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      end

      private

      def load_links
        profile = current_profile
        @profile_links = profile.profile_links.includes(:link).order(position: :asc)
        @available_links = profile.user.links.where.not(id: profile.link_ids).order(created_at: :desc)
        @spark = LinkClickSeriesService.call(@profile_links.map(&:link_id), days: 7)
      end

      # Strict boolean — ActiveModel casts nil/absent to nil, but the pinned /
      # visible columns are NOT NULL, so coerce to true/false.
      def bool(value)
        ActiveModel::Type::Boolean.new.cast(value) == true
      end
    end
  end
end
