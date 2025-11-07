class AddStatusToBrandPages < ActiveRecord::Migration[7.2]
  def change
    # Add status column with explicit default value 'DRAFT'
    add_column :brand_pages, :status, :string, default: 'DRAFT', null: false

    # Add index for efficient status queries
    add_index :brand_pages, :status

    # Set status to 'PUBLISHED' for any existing published records
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE brand_pages
          SET status = 'PUBLISHED'
          WHERE published_version_id IS NOT NULL
        SQL
      end
    end
  end
end
