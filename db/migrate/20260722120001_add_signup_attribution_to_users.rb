# frozen_string_literal: true

# First-touch marketing attribution captured at account creation (LevelCode sign-in). The SPA persists the
# campaign channel from the landing URL (?linkedin=…/?youtube=…/utm_*) and sends it on /ai/auth/verify;
# Levelcode::WebController records a sanitized copy here on the NEW user only. Nullable — null means the
# account predates attribution or arrived organically.
class AddSignupAttributionToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :signup_attribution, :jsonb
  end
end
