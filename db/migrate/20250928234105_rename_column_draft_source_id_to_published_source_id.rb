class RenameColumnDraftSourceIdToPublishedSourceId < ActiveRecord::Migration[7.2]
  def change
    rename_column :brand_pages, :draft_source_id, :published_source_id

    # Update the index name as well
    remove_index :brand_pages, :draft_source_id if index_exists?(:brand_pages, :draft_source_id)
    add_index :brand_pages, :published_source_id unless index_exists?(:brand_pages, :published_source_id)
  end
end
