# == Schema Information
#
# Table name: link_destination_histories
#
#  id              :bigint           not null, primary key
#  active_from     :datetime         not null
#  active_until    :datetime
#  destination_url :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  link_id         :bigint           not null
#
# Indexes
#
#  index_link_destination_histories_on_link_id                  (link_id)
#  index_link_destination_histories_on_link_id_and_active_from  (link_id,active_from)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
class LinkDestinationHistory < ApplicationRecord
  belongs_to :link

  validates :destination_url, presence: true
  validates :active_from, presence: true

  scope :current, -> { where(active_until: nil) }
  scope :chronological, -> { order(:active_from) }
end
