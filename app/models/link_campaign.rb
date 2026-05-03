# == Schema Information
#
# Table name: link_campaigns
#
#  id           :bigint           not null, primary key
#  accent_color :string           default("#7c3aed"), not null
#  description  :text
#  name         :string           not null
#  state        :string           default("active"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_link_campaigns_on_accent_color  (accent_color)
#  index_link_campaigns_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class LinkCampaign < ApplicationRecord
  STATES = %w[active paused archived expired].freeze
  HEX_COLOR = /\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/

  belongs_to :user
  has_many :links, dependent: :nullify

  validates :name, presence: true
  validates :state, inclusion: { in: STATES }
  validates :accent_color, format: { with: HEX_COLOR }

  scope :active, -> { where(state: "active") }

  # Pause all links in this campaign.
  def pause_all!(user: nil, reason: nil)
    transition_links!("paused", user: user, reason: reason || "Campaign paused")
  end

  # Resume all paused links in this campaign.
  def resume_all!(user: nil, reason: nil)
    transition_links!("active", user: user, reason: reason || "Campaign resumed")
  end

  # Expire all links in this campaign.
  def expire_all!(user: nil, reason: nil)
    transition_links!("expired", user: user, reason: reason || "Campaign expired")
  end

  private

  def transition_links!(new_state, user: nil, reason: nil)
    transaction do
      links.where.not(state: new_state).find_each do |link|
        link.transition_to!(new_state, user: user, reason: reason)
      end
      update!(state: new_state == "active" ? "active" : new_state)
    end
  end
end
