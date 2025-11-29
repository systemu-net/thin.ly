# == Schema Information
#
# Table name: clicks
#
#  id         :bigint           not null, primary key
#  country    :string
#  ip_address :string
#  referrer   :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :bigint           not null
#
# Indexes
#
#  index_clicks_on_link_id  (link_id)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
class Click < ApplicationRecord
  belongs_to :link, counter_cache: true
end
