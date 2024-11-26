class AddUserToLinks < ActiveRecord::Migration[7.2]
  def change
    add_reference :links, :user, null: false, foreign_key: true
  end
end
