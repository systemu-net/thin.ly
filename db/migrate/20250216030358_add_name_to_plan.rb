class AddNameToPlan < ActiveRecord::Migration[7.2]
  def change
    add_column :plans, :name, :string, null: false, default: "Free"
  end
end
