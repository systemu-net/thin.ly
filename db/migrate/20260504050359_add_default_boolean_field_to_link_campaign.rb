class AddDefaultBooleanFieldToLinkCampaign < ActiveRecord::Migration[7.2]
  def change
    add_column :link_campaigns, :default, :boolean, default: false, null: false
  end
end
