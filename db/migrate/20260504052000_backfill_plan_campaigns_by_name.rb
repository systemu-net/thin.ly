class BackfillPlanCampaignsByName < ActiveRecord::Migration[7.2]
  def up
    say_with_time "Backfilling plans.campaigns from plan name" do
      execute <<~SQL
        UPDATE plans
        SET campaigns = CASE
          WHEN LOWER(name) = 'creator' THEN 3
          WHEN LOWER(name) = 'influencer' THEN 10
          WHEN LOWER(name) = 'business' THEN 30
          ELSE 1
        END
      SQL
    end
  end

  def down
    # Data migration is intentionally irreversible.
  end
end
