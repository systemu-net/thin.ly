class AddTitleToBrandPages < ActiveRecord::Migration[7.2]
  def change
    add_column :brand_pages, :title, :string, null: false, default: "Untitled"
  end
end
