class QrCode < ApplicationRecord
  belongs_to :link
  belongs_to :user

  validates :user_id, uniqueness: { scope: :link_id }
  validates :image, presence: true

  mount_uploader :image, QrCodeUploader
end
