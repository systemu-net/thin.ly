class AddBudgetToCreditWallets < ActiveRecord::Migration[7.2]
  # M14 credit metering: enforce a DOLLAR compute budget (micro-$) instead of raw token caps. The
  # token columns stay as informational per-period aggregates; budget_micros/spent_micros are the
  # new enforcement pair. Backfill each wallet's budget from its plan (free wallets get the free
  # budget); spent stays 0 — the period's Redis counter + RecordUsageJob repopulate it.
  def up
    add_column :credit_wallets, :budget_micros, :bigint, null: false, default: 0
    add_column :credit_wallets, :spent_micros,  :bigint, null: false, default: 0

    say_with_time "backfilling budget_micros from plan" do
      CreditWallet.reset_column_information
      CreditWallet.where(product: Levelcode::PRODUCT).find_each do |w|
        budget = w.plan_key == Levelcode::FREE_PLAN_KEY ? Levelcode.free_budget_micros : Levelcode.budget_micros(w.plan_key)
        w.update_columns(budget_micros: budget.to_i)
      end
    end
  end

  def down
    remove_column :credit_wallets, :budget_micros
    remove_column :credit_wallets, :spent_micros
  end
end
