# == Schema Information
#
# Table name: profile_links
#
#  id             :bigint           not null, primary key
#  pinned         :boolean          default(FALSE), not null
#  position       :integer          default(0), not null
#  tag            :string
#  title_override :string
#  visible        :boolean          default(TRUE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  link_id        :bigint           not null
#  profile_id     :bigint           not null
#
# Indexes
#
#  index_profile_links_on_link_id                  (link_id)
#  index_profile_links_on_profile_id               (profile_id)
#  index_profile_links_on_profile_id_and_link_id   (profile_id,link_id) UNIQUE
#  index_profile_links_on_profile_id_and_position  (profile_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#  fk_rails_...  (profile_id => profiles.id)
#
class ProfileLink < ApplicationRecord
  belongs_to :profile
  belongs_to :link

  validates :link_id, uniqueness: { scope: :profile_id }
  validates :title_override, length: { maximum: 80 }, allow_nil: true
  validates :tag, length: { maximum: 24 }, allow_nil: true
  validate :link_belongs_to_same_user

  # Display title: owner override, else the link's own title, else its slug.
  def display_title
    title_override.presence || link&.title.presence || link&.lookup_code
  end

  private

  def link_belongs_to_same_user
    return if link.nil? || profile.nil?
    errors.add(:link, "must belong to the profile owner") if link.user_id != profile.user_id
  end
end
