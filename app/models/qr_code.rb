# == Schema Information
#
# Table name: qr_codes
#
#  id          :bigint           not null, primary key
#  image       :string
#  scans_count :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  link_id     :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_qr_codes_on_link_id  (link_id)
#  index_qr_codes_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#  fk_rails_...  (user_id => users.id)
#
class QrCode < ApplicationRecord
  belongs_to :link
  belongs_to :user
  has_many :api_requests, as: :logable, dependent: :destroy
  has_many :resources, as: :linkable, dependent: :destroy
  has_many :brand_pages, through: :resources, source: :page
  has_many :scans, -> { where(source: "qr") }, through: :link, source: :clicks

  validates :user_id, uniqueness: { scope: :link_id }
  validates :image, presence: true

  mount_uploader :image, QrCodeUploader
end
