# == Schema Information
#
# Table name: clicks
#
#  id         :integer          not null, primary key
#  country    :string
#  ip_address :string
#  referrer   :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :integer          not null
#
# Indexes
#
#  index_clicks_on_link_id  (link_id)
#
# Foreign Keys
#
#  link_id  (link_id => links.id)
#
require 'rails_helper'

RSpec.describe Click, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
