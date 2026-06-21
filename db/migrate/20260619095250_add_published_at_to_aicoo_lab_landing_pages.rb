class AddPublishedAtToAicooLabLandingPages < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_lab_landing_pages, :published_at, :datetime
  end
end
