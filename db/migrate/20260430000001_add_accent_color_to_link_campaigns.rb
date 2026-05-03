class AddAccentColorToLinkCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :link_campaigns, :accent_color, :string, default: "#7c3aed", null: false
    add_index :link_campaigns, :accent_color
  end
end
