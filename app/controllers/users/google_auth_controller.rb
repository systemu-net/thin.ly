# frozen_string_literal: true

class Users::GoogleAuthController < Devise::SessionsController
  include RackSessionFix
  respond_to :json

  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :require_no_authentication, raise: false

  def create
    id_token = params[:id_token] || params.dig(:user, :id_token)
    return render_unauthorized("Missing id_token") if id_token.blank?

    payload = verify_google_id_token(id_token)
    return render_unauthorized("Invalid Google token") unless payload

    user = User.from_google(payload, terms_accepted: params[:terms_accepted])

    if user&.persisted?
      sign_in :user, user
      self.resource = user
      respond_with(user)
    else
      message = user ? user.errors.full_messages.to_sentence : "Email not verified by Google"
      render json: { message: "Could not authenticate with Google. #{message}" },
             status: :unprocessable_content
    end
  end

  private

  def respond_with(_resource, _opts = {})
    render "users/sessions/create", status: :ok
  end

  def verify_google_id_token(id_token)
    Google::Auth::IDTokens.verify_oidc(id_token, aud: google_client_ids)
  rescue Google::Auth::IDTokens::VerificationError => e
    Rails.logger.warn "Google ID token verification failed: #{e.message}"
    nil
  end

  def google_client_ids
    ids = ENV["GOOGLE_CLIENT_ID"].to_s.split(",").map(&:strip).reject(&:empty?)
    ids.size == 1 ? ids.first : ids
  end

  def render_unauthorized(message)
    render json: { message: message }, status: :unauthorized
  end
end
