class AddClicksCountToLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :links, :clicks_count, :integer, default: 0, null: false

    # Backfill existing records
    reversible do |dir|
      dir.up do
        Link.find_each do |link|
          Link.reset_counters(link.id, :clicks)
        end
      end
    end
  end
end
