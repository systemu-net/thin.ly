class BackfillProfilesForExistingUsers < ActiveRecord::Migration[7.2]
  # Migration-local models so this stays correct regardless of future app-model
  # changes. Gives every existing user a Profile with a unique handle derived
  # from their email local-part.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationProfile < ActiveRecord::Base
    self.table_name = "profiles"
  end

  def up
    existing_handles = MigrationProfile.pluck(:handle).map(&:downcase).to_set

    MigrationUser.where.not(id: MigrationProfile.select(:user_id)).find_each do |user|
      base = user.email.to_s.split("@").first.to_s.downcase.gsub(/[^a-z0-9_.-]/, "")
      base = "user#{user.id}" if base.blank?

      handle = base
      suffix = 1
      while existing_handles.include?(handle)
        handle = "#{base}#{suffix}"
        suffix += 1
      end
      existing_handles << handle

      MigrationProfile.create!(
        user_id: user.id,
        handle: handle,
        display_name: base,
        created_at: Time.current,
        updated_at: Time.current
      )
    end
  end

  def down
    # Drop only the auto-created profiles; safe because the table came with this
    # feature. (The CreateProfiles migration's `down` removes the table anyway.)
    MigrationProfile.delete_all
  end
end
