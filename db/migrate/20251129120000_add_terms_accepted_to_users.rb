class AddTermsAcceptedToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :terms_accepted, :boolean, default: false, null: false
  end
end
