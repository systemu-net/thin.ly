class BackfillDefaultCampaignsForUsers < ActiveRecord::Migration[7.2]
  def up
    say_with_time "Creating default campaigns and assigning ungrouped links" do
      User.find_each do |user|
        campaign = user.link_campaigns.find_or_create_by!(default: true) do |record|
          record.name = "Default"
          record.description = "Default campaign"
          record.state = "active"
        end

        user.links.where(link_campaign_id: nil).update_all(
          link_campaign_id: campaign.id,
          updated_at: Time.current
        )
      end
    end
  end

  def down
    say_with_time "Removing default campaigns and unassigning links" do
      LinkCampaign.where(default: true).find_each do |campaign|
        campaign.links.update_all(link_campaign_id: nil, updated_at: Time.current)
        campaign.destroy!
      end
    end
  end
end
