class RenamePagesToBrandPagesInPlans < ActiveRecord::Migration[7.2]
  def change
    rename_column :plans, :pages, :brand_pages
  end
end
