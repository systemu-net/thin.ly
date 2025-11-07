class AddPublishedUrlToBrandPages < ActiveRecord::Migration[7.2]
  def change
    add_column :brand_pages, :published_url, :string
  end
end
