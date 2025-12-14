class AddSortingIndexesToLinks < ActiveRecord::Migration[7.2]
  def change
    # Index for sorting by created_at (user_id, created_at)
    add_index :links, [ :user_id, :created_at ], name: "index_links_on_user_and_created"

    # Index for sorting by clicks_count (user_id, clicks_count)
    add_index :links, [ :user_id, :clicks_count ], name: "index_links_on_user_and_clicks_count"
  end
end
