# == Schema Information
#
# Table name: link_routing_rules
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  conditions      :jsonb
#  destination_url :string           not null
#  priority        :integer          default(0), not null
#  rule_type       :string           not null
#  weight          :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  link_id         :bigint           not null
#
# Indexes
#
#  index_link_routing_rules_on_link_id               (link_id)
#  index_link_routing_rules_on_link_id_and_priority  (link_id,priority)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
FactoryBot.define do
  factory :link_routing_rule do
    association :link
    rule_type { "geo" }
    conditions { { "countries" => [ "US" ] } }
    destination_url { "https://us.example.com" }
    priority { 0 }
    active { true }

    trait :device do
      rule_type { "device" }
      conditions { { "device_types" => [ "mobile" ] } }
      destination_url { "https://m.example.com" }
    end

    trait :referrer do
      rule_type { "referrer" }
      conditions { { "referrer_pattern" => "twitter\\.com|x\\.com" } }
      destination_url { "https://twitter-landing.example.com" }
    end

    trait :time_window do
      rule_type { "time_window" }
      conditions { { "start_time" => "09:00", "end_time" => "17:00", "timezone" => "America/New_York" } }
      destination_url { "https://business-hours.example.com" }
    end

    trait :percentage do
      rule_type { "percentage" }
      conditions { {} }
      destination_url { "https://variant-a.example.com" }
      weight { 50 }
    end
  end
end
