class AddBusinessTypeToBusinesses < ActiveRecord::Migration[8.0]
  def up
    add_column :businesses, :business_type, :string, default: "other", null: false
    add_index :businesses, :business_type

    execute <<~SQL.squish
      UPDATE businesses
      SET business_type = CASE
        WHEN name = '吸えログ' THEN 'seo_media'
        WHEN name = 'AICOO Analytics Import' THEN 'internal_tool'
        WHEN LOWER(name) LIKE '%vault%' THEN 'saas'
        WHEN source IN ('aicoo_lab', 'idea_pipeline') THEN 'landing_page'
        WHEN created_by_aicoo = TRUE AND lifecycle_stage IN ('idea', 'lp_validation') THEN 'landing_page'
        ELSE business_type
      END
    SQL
  end

  def down
    remove_index :businesses, :business_type
    remove_column :businesses, :business_type
  end
end
