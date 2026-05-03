require "rails_helper"

RSpec.describe RoutingRulesEngine do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user, governance_enabled: true) }

  describe ".evaluate" do
    context "geo rules" do
      it "matches when country is in the list" do
        rule = create(:link_routing_rule, link: link, rule_type: "geo",
                      conditions: { "countries" => [ "US", "CA" ] },
                      destination_url: "https://us.example.com")

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { country: "US" })
        expect(result).to eq(rule)
      end

      it "does not match when country is not in the list" do
        create(:link_routing_rule, link: link, rule_type: "geo",
               conditions: { "countries" => [ "US" ] },
               destination_url: "https://us.example.com")

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { country: "DE" })
        expect(result).to be_nil
      end

      it "is case-insensitive for country matching" do
        rule = create(:link_routing_rule, link: link, rule_type: "geo",
                      conditions: { "countries" => [ "us" ] },
                      destination_url: "https://us.example.com")

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { country: "US" })
        expect(result).to eq(rule)
      end
    end

    context "device rules" do
      it "matches when device_type matches" do
        rule = create(:link_routing_rule, :device, link: link)

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { device_type: "mobile" })
        expect(result).to eq(rule)
      end

      it "does not match wrong device type" do
        create(:link_routing_rule, :device, link: link)

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { device_type: "desktop" })
        expect(result).to be_nil
      end
    end

    context "referrer rules" do
      it "matches when referrer matches pattern" do
        rule = create(:link_routing_rule, :referrer, link: link)

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { referrer: "https://twitter.com/post/123" })
        expect(result).to eq(rule)
      end

      it "does not match unrelated referrer" do
        create(:link_routing_rule, :referrer, link: link)

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { referrer: "https://google.com" })
        expect(result).to be_nil
      end
    end

    context "time_window rules" do
      it "matches during the time window" do
        rule = create(:link_routing_rule, :time_window, link: link,
                      conditions: { "start_time" => "00:00", "end_time" => "23:59", "timezone" => "UTC" })

        result = described_class.evaluate(LinkRoutingRule.where(link: link), { timestamp: Time.current })
        expect(result).to eq(rule)
      end

      it "does not match outside the time window" do
        create(:link_routing_rule, :time_window, link: link,
               conditions: { "start_time" => "03:00", "end_time" => "04:00", "timezone" => "UTC" })

        # Use a time clearly outside the window
        time = Time.utc(2025, 1, 1, 12, 0, 0) # noon UTC
        result = described_class.evaluate(LinkRoutingRule.where(link: link), { timestamp: time })
        expect(result).to be_nil
      end
    end

    context "percentage rules" do
      it "returns one of the percentage rules" do
        rule_a = create(:link_routing_rule, :percentage, link: link,
                        destination_url: "https://a.example.com", weight: 50)
        rule_b = create(:link_routing_rule, :percentage, link: link,
                        destination_url: "https://b.example.com", weight: 50)

        results = 100.times.map { described_class.evaluate(LinkRoutingRule.where(link: link), {}) }
        expect(results.uniq.map(&:id)).to match_array([ rule_a.id, rule_b.id ])
      end
    end

    context "priority ordering" do
      it "returns higher-priority rule when both match" do
        create(:link_routing_rule, link: link, rule_type: "geo",
               conditions: { "countries" => [ "US" ] },
               destination_url: "https://low-priority.example.com",
               priority: 10)
        high = create(:link_routing_rule, link: link, rule_type: "device",
                      conditions: { "device_types" => [ "mobile" ] },
                      destination_url: "https://high-priority.example.com",
                      priority: 1)

        # Both rules match the context; the engine processes by priority order
        result = described_class.evaluate(
          LinkRoutingRule.where(link: link).order(:priority),
          { country: "US", device_type: "mobile" }
        )
        expect(result).to eq(high)
      end
    end
  end
end
