class AddSortOrderToResources < ActiveRecord::Migration[7.2]
  def change
    add_column :resources, :sort_order, :integer, default: 0, null: false
    add_index :resources, [ :page_id, :sort_order ], name: 'index_resources_on_page_id_and_sort_order'
  end
end
