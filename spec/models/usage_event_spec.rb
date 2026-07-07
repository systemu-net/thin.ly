# == Schema Information
#
# Table name: usage_events
#
#  id                  :bigint           not null, primary key
#  cached_input_tokens :bigint           default(0), not null
#  cost_micros         :bigint           default(0), not null
#  input_tokens        :bigint           default(0), not null
#  model               :string
#  output_tokens       :bigint           default(0), not null
#  provider            :string
#  created_at          :datetime         not null
#  request_id          :string
#  user_id             :bigint           not null
#
# Indexes
#
#  index_usage_events_on_request_id_unique       (request_id) UNIQUE WHERE (request_id IS NOT NULL)
#  index_usage_events_on_user_id                 (user_id)
#  index_usage_events_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe UsageEvent, type: :model do
  let(:user) { create(:user) }

  describe 'associations' do
    it 'belongs to a user' do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end
  end

  describe 'validations' do
    it 'is valid with non-negative token counts' do
      event = user.usage_events.build(
        request_id: 'req_1',
        model: Levelcode::DEFAULT_MODEL,
        provider: 'openrouter',
        input_tokens: 40_000,
        output_tokens: 3_000,
        cached_input_tokens: 20_000,
        cost_micros: 123
      )
      expect(event).to be_valid
    end

    it 'rejects negative token counts' do
      event = user.usage_events.build(input_tokens: -1)
      expect(event).not_to be_valid
    end
  end

  describe '#cost_dollars' do
    it 'converts micro-dollars to dollars' do
      event = user.usage_events.build(cost_micros: 1_500_000)
      expect(event.cost_dollars).to eq(1.5)
    end
  end
end
