class FixReservedProfileHandles < ActiveRecord::Migration[7.2]
  # The original backfill (20260620235156) minted handles from email local-parts
  # without checking the reserved list (it used a validation-free migration-local
  # model), so e.g. admin@… became @admin. Rename any reserved handle to a safe,
  # unique one. Runs after the backfill in every environment, so both already-
  # migrated and fresh databases converge to a correct state.
  def up
    Profile.reset_column_information

    Profile.find_each do |profile|
      next unless Profile::RESERVED_HANDLES.include?(profile.handle.to_s.downcase)

      base = profile.user.email.to_s.split("@").first.presence || "user#{profile.user_id}"
      new_handle = Profile.generate_unique_handle(base)

      say "Renaming reserved handle @#{profile.handle} -> @#{new_handle} (user ##{profile.user_id})"
      profile.update_columns(handle: new_handle, updated_at: Time.current)
    end
  end

  def down
    # Irreversible: we don't restore reserved handles (they should never exist).
  end
end
