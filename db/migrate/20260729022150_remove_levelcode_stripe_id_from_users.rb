class RemoveLevelcodeStripeIdFromUsers < ActiveRecord::Migration[7.2]
  # `users.levelcode_stripe_id` never had a migration behind it. It entered db/schema.rb in
  # b7b2cfc ("Add annotations", 2026-07-22), a commit that touched only the schema dump and
  # the annotation comments: an annotate run regenerated the schema from a local database
  # where the column had been added by hand, and that snapshot was committed.
  #
  # So whether it exists depends on how each database was built:
  #
  #   db:schema:load  (development, test, CI)  -> column present, always NULL
  #   migrations      (production)             -> column absent entirely
  #
  # Which is why both directions are guarded. An unconditional `remove_column` would raise
  # PG::UndefinedColumn on production, where there is nothing to remove — the migration has
  # to be a no-op there while still cleaning up every database that loaded the schema.
  #
  # Nothing reads or writes the column: every Stripe customer id the application has ever
  # stored lives in `users.stripe_id`. Dropping it makes db/schema.rb describe production
  # accurately again, which it has not done since 2026-07-22.
  def up
    return unless column_exists?(:users, :levelcode_stripe_id)

    remove_column :users, :levelcode_stripe_id
  end

  # Restores the pre-migration schema. Postgres drops the dependent index along with the
  # column, so rolling back has to recreate the index as well as the column.
  def down
    return if column_exists?(:users, :levelcode_stripe_id)

    add_column :users, :levelcode_stripe_id, :string
    add_index :users, :levelcode_stripe_id,
              unique: true,
              where: "levelcode_stripe_id IS NOT NULL",
              name: "index_users_on_levelcode_stripe_id"
  end
end
