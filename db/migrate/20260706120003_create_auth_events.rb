class CreateAuthEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :auth_events do |t|
      # user_id is NULL for a failed attempt where no account resolved (bad email, etc.).
      t.references :user, null: true, foreign_key: true

      t.string :email                 # the address the attempt was for (present even on failure)
      t.string :kind,    null: false  # email | oauth | exchange | login | refresh
      t.string :provider              # github | google (for oauth), else null
      t.string :outcome, null: false  # success | failure
      t.string :reason                # short failure code (invalid_code, oauth_failed, …)
      t.string :ip
      t.string :country               # CDN edge country (CF-IPCountry / CloudFront-Viewer-Country)

      t.datetime :created_at, null: false
    end

    add_index :auth_events, :created_at
    add_index :auth_events, :outcome
    add_index :auth_events, :email
  end
end
