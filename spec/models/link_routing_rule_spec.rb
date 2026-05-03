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
require "rails_helper"

RSpec.describe LinkRoutingRule, type: :model do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }

  describe "validations" do
    it "requires a valid rule_type" do
      rule = build(:link_routing_rule, link: link, rule_type: "invalid")
      expect(rule).not_to be_valid
    end

    it "allows all valid rule types" do
      %w[geo device referrer time_window percentage].each do |type|
        rule = build(:link_routing_rule, link: link, rule_type: type)
        rule.weight = 50 if type == "percentage"
        expect(rule).to be_valid, "Expected #{type} to be valid"
      end
    end

    it "requires a destination_url" do
      rule = build(:link_routing_rule, link: link, destination_url: nil)
      expect(rule).not_to be_valid
    end

    it "validates destination_url format" do
      rule = build(:link_routing_rule, link: link, destination_url: "not a url")
      expect(rule).not_to be_valid
    end

    it "validates weight for percentage rules" do
      rule = build(:link_routing_rule, :percentage, link: link, weight: 150)
      expect(rule).not_to be_valid
    end
  end
end
