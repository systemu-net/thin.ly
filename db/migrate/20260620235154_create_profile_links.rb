class CreateProfileLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :profile_links do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :link,    null: false, foreign_key: true

      t.integer :position, null: false, default: 0
      t.boolean :pinned,   null: false, default: false
      t.boolean :visible,  null: false, default: true
      t.string  :title_override
      t.string  :tag

      t.timestamps
    end

    # A given link appears at most once on a profile.
    add_index :profile_links, [ :profile_id, :link_id ], unique: true
    add_index :profile_links, [ :profile_id, :position ]
  end
end
