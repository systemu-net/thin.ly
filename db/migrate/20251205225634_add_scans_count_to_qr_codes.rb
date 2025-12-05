class AddScansCountToQrCodes < ActiveRecord::Migration[7.2]
  def change
    add_column :qr_codes, :scans_count, :integer, default: 0, null: false
  end
end
