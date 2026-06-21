# == Schema Information
#
# Table name: profiles
#
#  id              :bigint           not null, primary key
#  accent          :string           default("violet"), not null
#  bio             :text
#  display_name    :string
#  followers_count :integer          default(0), not null
#  following_count :integer          default(0), not null
#  handle          :string           not null
#  location        :string
#  privacy         :jsonb            not null
#  published_at    :datetime
#  socials         :jsonb            not null
#  verified        :boolean          default(FALSE), not null
#  website         :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_profiles_on_lower_handle  (lower((handle)::text)) UNIQUE
#  index_profiles_on_user_id       (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Profile < ApplicationRecord
  HANDLE_FORMAT = /\A[a-z0-9_.-]+\z/
  ACCENTS = %w[violet mint coral peach lilac sun sky].freeze
  SOCIAL_KEYS = %w[instagram youtube spotify tiktok x website].freeze

  # App routes / product words that must ALWAYS be reserved (defence-in-depth
  # against route collisions, even if the blocklist file is edited or missing).
  CORE_RESERVED_HANDLES = %w[
    api app www admin settings login logout signin signup register
    dashboard profile profiles user users me pages page links link qr qrcode
    campaigns analytics governance new edit about pricing terms privacy cookies
    legal billing checkout thin thinly
  ].freeze

  # The full blocklist: the core routes above, plus the curated + vendored
  # blocklist in config/reserved_handles.txt (system words, roles, RFC mailboxes,
  # brands/trademarks). Comments (#) and blank lines are ignored. Loaded once at
  # boot into a Set for O(1) lookups. See that file for sources/rationale.
  RESERVED_HANDLES_FILE = Rails.root.join("config", "reserved_handles.txt")
  RESERVED_HANDLES = begin
    from_file = File.exist?(RESERVED_HANDLES_FILE) ? File.readlines(RESERVED_HANDLES_FILE, chomp: true) : []
    (CORE_RESERVED_HANDLES + from_file)
      .map { |line| line.to_s.strip.downcase }
      .reject { |line| line.empty? || line.start_with?("#") }
      .to_set
      .freeze
  end

  PRIVACY_KEYS = %w[is_public show_followers allow_follow allow_messages].freeze
  DEFAULT_PRIVACY = {
    "is_public" => true,
    "show_followers" => true,
    "allow_follow" => true,
    "allow_messages" => false
  }.freeze

  belongs_to :user
  has_many :profile_links, -> { order(position: :asc) }, dependent: :destroy
  has_many :links, through: :profile_links

  before_validation :normalize_handle

  validates :handle,
    presence: true,
    format: { with: HANDLE_FORMAT, message: "may only contain lowercase letters, numbers, dots, dashes and underscores" },
    length: { in: 2..30 },
    uniqueness: { case_sensitive: false }
  validate :handle_not_reserved
  validates :bio, length: { maximum: 160 }, allow_nil: true
  validates :accent, inclusion: { in: ACCENTS }

  scope :public_profiles, -> { where("privacy ->> 'is_public' = 'true'") }

  def self.find_by_handle(value)
    where("lower(handle) = ?", value.to_s.downcase.delete_prefix("@")).first
  end

  # Derive a valid, unique, non-reserved handle from a base string (e.g. an
  # email local-part). Appends a numeric suffix until it clears the reserved
  # list and the uniqueness check. Single source of truth for handle minting.
  def self.generate_unique_handle(base)
    candidate = base.to_s.downcase.gsub(/[^a-z0-9_.-]/, "")
    candidate = "user#{candidate}" if candidate.length < 2
    candidate = candidate[0, 28]

    handle = candidate
    suffix = 1
    while RESERVED_HANDLES.include?(handle) || where("lower(handle) = ?", handle).exists?
      handle = "#{candidate}#{suffix}"
      suffix += 1
    end
    handle
  end

  def to_param
    handle
  end

  def published?
    published_at.present?
  end

  # Whether to show the blue "verified" badge: a paid-plan perk (X-style), or a
  # platform-set override on the `verified` column.
  def verified_badge?
    verified? || user.verified_member?
  end

  # Public URL of the profile — points at the SPA host that renders /@handle.
  def public_url
    base =
      if Rails.env.production?
        "https://thin.ly"
      else
        ENV["PROFILE_HOST"].presence || "http://localhost:4000"
      end
    "#{base}/@#{handle}"
  end

  # Privacy accessors (privacy is a jsonb blob with string keys).
  PRIVACY_KEYS.each do |flag|
    define_method("#{flag}?") { ActiveModel::Type::Boolean.new.cast(privacy&.dig(flag)) }
  end

  # The links a visitor may see: curated, visible, and currently active per the
  # governance state on the underlying Link. Pinned first, then by position.
  def public_profile_links
    profile_links
      .includes(:link)
      .select { |pl| pl.visible? && pl.link&.state == "active" }
      .sort_by { |pl| [ pl.pinned? ? 0 : 1, pl.position ] }
  end

  private

  def normalize_handle
    self.handle = handle.to_s.strip.downcase.delete_prefix("@").presence
  end

  def handle_not_reserved
    return if handle.blank?
    errors.add(:handle, "is reserved") if RESERVED_HANDLES.include?(handle)
  end
end
