class AddTitleAndDescriptionToLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :links, :title, :string
    add_column :links, :description, :text
  end
end
