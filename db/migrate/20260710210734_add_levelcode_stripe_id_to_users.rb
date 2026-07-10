# frozen_string_literal: true

# LevelCode billing runs on a SEPARATE Stripe account from the linkly shortener, so a
# user who buys both products has TWO Stripe customer ids. `stripe_id` stays the linkly
# customer; this holds the LevelCode-account customer (minted lazily on first checkout).
# Partial-unique so the many users who never buy LevelCode (NULL) don't collide.
class AddLevelcodeStripeIdToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :levelcode_stripe_id, :string
    add_index :users, :levelcode_stripe_id, unique: true, where: "levelcode_stripe_id IS NOT NULL"
  end
end
