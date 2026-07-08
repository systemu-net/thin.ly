# Post-rename cleanup: the LevelCode wallet product tag is now "levelcode"
# (Levelcode::PRODUCT). The column default was left at the pre-rename "atompp".
# Fix the default, and migrate any pre-rename wallets — but only where the user
# doesn't already have a "levelcode" wallet (the [user_id, product] unique index
# would otherwise reject the update).
class ChangeCreditWalletsProductDefault < ActiveRecord::Migration[7.2]
  def up
    change_column_default :credit_wallets, :product, from: "atompp", to: "levelcode"

    execute <<~SQL.squish
      UPDATE credit_wallets w
         SET product = 'levelcode'
       WHERE w.product = 'atompp'
         AND NOT EXISTS (
           SELECT 1 FROM credit_wallets w2
            WHERE w2.user_id = w.user_id AND w2.product = 'levelcode'
         )
    SQL
  end

  def down
    change_column_default :credit_wallets, :product, from: "levelcode", to: "atompp"
  end
end
