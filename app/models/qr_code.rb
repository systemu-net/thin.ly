class QrCode < ApplicationRecord
  belongs_to :link
  belongs_to :user

  validates :user_id, uniqueness: { scope: :link_id }
end
