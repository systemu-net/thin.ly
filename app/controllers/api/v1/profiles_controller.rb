module Api
  module V1
    # Owner-side management of the current user's public @handle profile.
    # (The public, by-handle read endpoint lives in PublicProfilesController.)
    class ProfilesController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token

      # GET /api/v1/profile
      def show
        @profile = current_profile
        render :show, status: :ok
      end

      # PATCH /api/v1/profile
      def update
        @profile = current_profile

        if @profile.update(merged_profile_attributes)
          render :show, status: :ok
        else
          render json: { errors: @profile.errors.full_messages }, status: :unprocessable_content
        end
      end

      # POST /api/v1/profile/publish
      # Makes the profile live (first publish stamps published_at).
      def publish
        @profile = current_profile
        @profile.update!(published_at: Time.current)
        render :show, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      end

      # GET /api/v1/handles/check?handle=foo
      # Live availability check for the editor's handle field.
      def check_handle
        handle = params[:handle].to_s.strip.downcase.delete_prefix("@")
        available, reason = handle_availability(handle)
        render json: { handle: handle, available: available, reason: reason }, status: :ok
      end

      private

      # Strong params. socials/privacy are jsonb; we merge partial updates into
      # the existing blobs and restrict to known keys so a PATCH can't wipe or
      # inject arbitrary keys.
      def merged_profile_attributes
        permitted = params.require(:profile).permit(
          :handle, :display_name, :bio, :location, :website, :accent,
          socials: Profile::SOCIAL_KEYS.map(&:to_sym),
          privacy: Profile::PRIVACY_KEYS.map(&:to_sym)
        )

        if permitted.key?(:socials)
          incoming = permitted[:socials].to_h.stringify_keys.slice(*Profile::SOCIAL_KEYS)
          permitted[:socials] = current_profile.socials.to_h.merge(incoming)
        end

        if permitted.key?(:privacy)
          incoming = permitted[:privacy].to_h.stringify_keys.slice(*Profile::PRIVACY_KEYS)
            .transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
          permitted[:privacy] = current_profile.privacy.to_h.merge(incoming)
        end

        permitted
      end

      def handle_availability(handle)
        return [ false, "too_short" ] if handle.length < 2
        return [ false, "too_long" ] if handle.length > 30
        return [ false, "invalid" ] unless handle.match?(Profile::HANDLE_FORMAT)
        return [ false, "reserved" ] if Profile::RESERVED_HANDLES.include?(handle)

        taken = Profile.where("lower(handle) = ?", handle)
                       .where.not(id: current_profile.id)
                       .exists?
        return [ false, "taken" ] if taken

        [ true, nil ]
      end
    end
  end
end
