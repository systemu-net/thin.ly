class AddImageToQrCodes < ActiveRecord::Migration[7.2]
  def change
    add_column :qr_codes, :image, :string
  end
end
