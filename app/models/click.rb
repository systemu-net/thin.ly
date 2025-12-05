# == Schema Information
#
# Table name: clicks
#
#  id         :bigint           not null, primary key
#  country    :string
#  ip_address :string
#  referrer   :string
#  source     :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :bigint           not null
#
# Indexes
#
#  index_clicks_on_link_id  (link_id)
#  index_clicks_on_source   (source)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
class Click < ApplicationRecord
  belongs_to :link, counter_cache: true

  after_create :increment_qr_code_scans_count, if: :qr_scan?
  after_destroy :decrement_qr_code_scans_count, if: :qr_scan?

  private

  def qr_scan?
    source == "qr"
  end

  def increment_qr_code_scans_count
    qr_code = link.qr_codes.find_by(user_id: link.user_id)
    qr_code&.increment!(:scans_count)
  end

  def decrement_qr_code_scans_count
    qr_code = link.qr_codes.find_by(user_id: link.user_id)
    qr_code&.decrement!(:scans_count)
  end
end
