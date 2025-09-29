class CreateBrandPages < ActiveRecord::Migration[7.2]
  def change
    create_table :brand_pages do |t|
      t.references :user, null: false, foreign_key: true
      t.jsonb :content, null: false, default: {}
      t.datetime :published_at
      t.references :draft_source, foreign_key: { to_table: :brand_pages }, index: true
      t.string :lookup_code, null: false, index: { unique: true }

      t.timestamps
    end

    add_index :brand_pages, :published_at
  end
end
