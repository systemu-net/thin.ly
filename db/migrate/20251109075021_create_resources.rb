class CreateResources < ActiveRecord::Migration[7.2]
  def change
    create_table :resources do |t|
      t.references :page, null: false, foreign_key: { to_table: :brand_pages }
      t.references :linkable, polymorphic: true, null: false

      t.timestamps
    end

    add_index :resources, [ :page_id, :linkable_type, :linkable_id ], name: 'index_resources_on_page_and_linkable'
  end
end
