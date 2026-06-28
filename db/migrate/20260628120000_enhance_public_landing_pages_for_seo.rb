class EnhancePublicLandingPagesForSeo < ActiveRecord::Migration[8.1]
  def up
    add_column :aicoo_lab_landing_pages, :public_status, :string, null: false, default: "draft"
    add_column :aicoo_lab_landing_pages, :scheduled_publish_at, :datetime
    add_column :aicoo_lab_landing_pages, :seo_title, :string
    add_column :aicoo_lab_landing_pages, :seo_description, :text
    add_column :aicoo_lab_landing_pages, :og_title, :string
    add_column :aicoo_lab_landing_pages, :og_description, :text
    add_column :aicoo_lab_landing_pages, :og_image_url, :string
    add_column :aicoo_lab_landing_pages, :canonical_url, :string

    add_index :aicoo_lab_landing_pages, :public_status
    add_index :aicoo_lab_landing_pages, :scheduled_publish_at

    create_table :aicoo_lab_landing_page_slug_histories do |t|
      t.references :aicoo_lab_landing_page, null: false, foreign_key: true
      t.string :slug, null: false

      t.timestamps
    end

    add_index :aicoo_lab_landing_page_slug_histories, :slug, unique: true

    execute <<~SQL.squish
      UPDATE aicoo_lab_landing_pages
      SET public_status = CASE
        WHEN status = 'published' THEN 'published'
        WHEN status = 'unpublished' THEN 'archived'
        ELSE 'draft'
      END
    SQL
  end

  def down
    drop_table :aicoo_lab_landing_page_slug_histories

    remove_index :aicoo_lab_landing_pages, :scheduled_publish_at
    remove_index :aicoo_lab_landing_pages, :public_status

    remove_column :aicoo_lab_landing_pages, :canonical_url
    remove_column :aicoo_lab_landing_pages, :og_image_url
    remove_column :aicoo_lab_landing_pages, :og_description
    remove_column :aicoo_lab_landing_pages, :og_title
    remove_column :aicoo_lab_landing_pages, :seo_description
    remove_column :aicoo_lab_landing_pages, :seo_title
    remove_column :aicoo_lab_landing_pages, :scheduled_publish_at
    remove_column :aicoo_lab_landing_pages, :public_status
  end
end
