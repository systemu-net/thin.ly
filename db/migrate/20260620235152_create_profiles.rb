class CreateProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      # Public identity
      t.string :handle, null: false
      t.string :display_name
      t.text   :bio
      t.string :location
      t.string :website

      # Presentation
      t.string  :accent,   null: false, default: "violet" # tone key
      t.boolean :verified, null: false, default: false     # platform-managed

      # Flexible blobs
      t.jsonb :socials, null: false, default: {}
      t.jsonb :privacy, null: false, default: {
        "is_public" => true,
        "show_followers" => true,
        "allow_follow" => true,
        "allow_messages" => false
      }

      # Denormalised social counts (maintained by Follow once Phase 3 lands)
      t.integer :followers_count, null: false, default: 0
      t.integer :following_count, null: false, default: 0

      # null until the owner first publishes the public page
      t.datetime :published_at

      t.timestamps
    end

    # Case-insensitive uniqueness for handles (we store lowercased in the model).
    add_index :profiles, "lower(handle)", unique: true, name: "index_profiles_on_lower_handle"
  end
end
