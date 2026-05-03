class AddLinkGovernance < ActiveRecord::Migration[7.2]
  def change
    # ── Extend existing links table with governance columns ────────────────
    add_column :links, :state, :string, default: "active", null: false
    add_column :links, :governance_enabled, :boolean, default: false, null: false
    add_column :links, :activates_at, :datetime
    add_column :links, :expires_at, :datetime
    add_column :links, :click_cap, :integer
    add_column :links, :expired_redirect_url, :string
    add_column :links, :paused_redirect_url, :string
    add_column :links, :password_protected, :boolean, default: false, null: false
    add_column :links, :password_digest, :string

    add_index :links, :state
    add_index :links, :expires_at
    add_index :links, :activates_at

    # ── Link campaigns (group links for bulk operations) ──────────────────
    create_table :link_campaigns do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :name, null: false
      t.string     :state, default: "active", null: false
      t.text       :description
      t.timestamps
    end

    add_column :links, :link_campaign_id, :bigint
    add_index  :links, :link_campaign_id
    add_foreign_key :links, :link_campaigns

    # ── Routing rules — ordered, first-match wins ─────────────────────────
    create_table :link_routing_rules do |t|
      t.references :link, null: false, foreign_key: true
      t.string     :rule_type, null: false   # geo, device, referrer, time_window, percentage
      t.jsonb      :conditions, default: {}
      t.string     :destination_url, null: false
      t.integer    :weight                   # for percentage splits (0-100)
      t.integer    :priority, default: 0, null: false
      t.boolean    :active, default: true, null: false
      t.timestamps
    end

    add_index :link_routing_rules, [ :link_id, :priority ]

    # ── Governance audit trail ────────────────────────────────────────────
    create_table :link_governance_logs do |t|
      t.references :link, null: false, foreign_key: true
      t.references :user, foreign_key: true  # nil = system action
      t.string     :action, null: false      # state_change, destination_update, rule_added, etc.
      t.jsonb      :before_state, default: {}
      t.jsonb      :after_state, default: {}
      t.string     :reason
      t.string     :ip_address
      t.timestamps
    end

    add_index :link_governance_logs, [ :link_id, :created_at ]

    # ── Destination history — full trail of all URLs a link pointed to ────
    create_table :link_destination_histories do |t|
      t.references :link, null: false, foreign_key: true
      t.string     :destination_url, null: false
      t.datetime   :active_from, null: false
      t.datetime   :active_until
      t.timestamps
    end

    add_index :link_destination_histories, [ :link_id, :active_from ]
  end
end
