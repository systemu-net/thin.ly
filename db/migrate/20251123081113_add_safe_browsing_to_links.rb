class AddSafeBrowsingToLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :links, :is_safe, :boolean, default: nil
    add_column :links, :last_scanned_at, :datetime
    add_column :links, :scan_failures, :integer, default: 0

    add_index :links, :is_safe
    add_index :links, :last_scanned_at
    add_index :links, [ :is_safe, :last_scanned_at ] # For rescan queries
  end
end
