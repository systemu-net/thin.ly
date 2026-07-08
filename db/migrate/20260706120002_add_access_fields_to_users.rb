class AddAccessFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    # Denormalized "where/when did we last see this user" for the admin dashboard.
    # Country comes from the CDN edge header (CF-IPCountry / CloudFront-Viewer-Country);
    # both are updated (throttled) whenever an authenticated request resolves.
    add_column :users, :last_country, :string
    add_column :users, :last_seen_at, :datetime
    add_index  :users, :last_seen_at
  end
end
