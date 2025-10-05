class AddDescriptionToBrandPages < ActiveRecord::Migration[7.2]
  def change
    add_column :brand_pages, :description, :text
  end
end
