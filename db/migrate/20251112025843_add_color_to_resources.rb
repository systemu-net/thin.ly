class AddColorToResources < ActiveRecord::Migration[7.2]
  def change
    add_column :resources, :color, :string
  end
end
