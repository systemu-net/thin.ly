class AddSocialOrderToProfiles < ActiveRecord::Migration[7.2]
  def change
    # Ordered list of social platform keys (jsonb arrays preserve element order,
    # unlike the `socials` jsonb object whose keys Postgres normalizes). Drives
    # the order social icons render in on the public profile.
    add_column :profiles, :social_order, :jsonb, default: [], null: false
  end
end
