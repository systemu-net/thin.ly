# == Schema Information
#
# Table name: qr_codes
#
#  id         :integer          not null, primary key
#  image      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_qr_codes_on_link_id  (link_id)
#  index_qr_codes_on_user_id  (user_id)
#
# Foreign Keys
#
#  link_id  (link_id => links.id)
#  user_id  (user_id => users.id)
#
class QrCode < ApplicationRecord
  belongs_to :link
  belongs_to :user

  validates :user_id, uniqueness: { scope: :link_id }
  validates :image, presence: true

  mount_uploader :image, QrCodeUploader
end
