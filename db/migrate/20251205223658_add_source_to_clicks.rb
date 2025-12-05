class AddSourceToClicks < ActiveRecord::Migration[7.2]
  def change
    add_column :clicks, :source, :string
    add_index :clicks, :source
  end
end
