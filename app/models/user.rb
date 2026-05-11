# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  avatar                 :string
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  jti                    :string           not null
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  terms_accepted         :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  stripe_id              :string
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_jti                   (jti) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher
  include UserNotifier
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  has_many :links, dependent: :destroy
  has_many :link_campaigns, dependent: :destroy
  has_many :qr_codes, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :plans, through: :subscriptions
  has_many :brand_pages, dependent: :destroy

  mount_uploader :avatar, AvatarUploader

  before_validation :create_stripe_customer, on: :create
  before_validation :generate_default_avatar, on: :create, if: -> { avatar.blank? }
  before_commit :create_default_subscription, on: :create
  after_commit :create_default_campaign, on: :create
  after_destroy :delete_stripe_customer

  # Persisted column `terms_accepted` records explicit acceptance of terms.
  # Validate terms acceptance on signup — require boolean `true` on create.
  validates :terms_accepted,
            acceptance: { accept: true, message: "must be accepted" },
            on: :create

  GOOGLE_PROVIDER = "google_oauth2".freeze

  # Find or create a user from a verified Google ID token payload.
  # Auto-links by email only when Google asserts the email is verified.
  def self.from_google(payload, terms_accepted: nil)
    return nil unless payload && payload["email_verified"]

    uid = payload["sub"].to_s
    email = payload["email"].to_s.downcase

    user = find_by(provider: GOOGLE_PROVIDER, uid: uid) || find_by(email: email)

    if user
      user.update(provider: GOOGLE_PROVIDER, uid: uid) if user.uid.blank?
      user
    else
      create(
        provider: GOOGLE_PROVIDER,
        uid: uid,
        email: email,
        password: Devise.friendly_token[0, 20],
        terms_accepted: ActiveModel::Type::Boolean.new.cast(terms_accepted) || false
      )
    end
  end

  def retrieve_stripe_customer
    Stripe::Customer.retrieve(stripe_id)
  end

  def plan
    @plan ||= plans.first
  end

  def subscribed?
    subscriptions.where(status: "active").any?
  end

  private

  def create_stripe_customer
    return if stripe_id.present?

    customer = Stripe::Customer.create(email: email)
    self.stripe_id = customer.id
  end

  def delete_stripe_customer
    customer = retrieve_stripe_customer
    customer.delete
  end

  def create_default_subscription
    return if subscriptions.any?

    User.transaction do
      subscriptions.create(
        customer_id: stripe_id
      )
    end
  end

  def create_default_campaign
    link_campaigns.find_or_create_by!(default: true) do |campaign|
      campaign.name = "Default"
      campaign.description = "Default campaign"
      campaign.state = "active"
    end
  end

  def generate_default_avatar
    return if avatar.present?

    begin
      generator = JdenticonGenerator.new(email)
      self.avatar = generator.generate
    rescue => e
      Rails.logger.error "Failed to generate avatar for user #{email}: #{e.message}"
      # Don't fail user creation if avatar generation fails
    end
  end
end
