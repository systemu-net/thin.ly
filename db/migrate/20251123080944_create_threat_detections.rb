class CreateThreatDetections < ActiveRecord::Migration[7.2]
  def change
    create_table :threat_detections do |t|
      t.references :detectable, polymorphic: true, null: false, index: true
      t.string :url, null: false
      t.json :threat_types, default: [] # ["MALWARE", "SOCIAL_ENGINEERING", etc.]
      t.json :platform_types, default: [] # ["ANY_PLATFORM", "WINDOWS", etc.]
      t.string :severity # "HIGH", "MEDIUM", "LOW"
      t.string :status, default: 'active' # active, resolved, false_positive
      t.text :notes # Admin notes about resolution
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :threat_detections, :status
    add_index :threat_detections, :created_at
    add_index :threat_detections, [ :detectable_type, :detectable_id, :status ]
  end
end
