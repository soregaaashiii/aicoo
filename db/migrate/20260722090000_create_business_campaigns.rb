class CreateBusinessCampaigns < ActiveRecord::Migration[8.0]
  class MigrationBusiness < ActiveRecord::Base
    self.table_name = "businesses"
  end

  class MigrationCampaign < ActiveRecord::Base
    self.table_name = "business_campaigns"
  end

  class MigrationPrototype < ActiveRecord::Base
    self.table_name = "business_prototypes"
  end

  def up
    create_table :business_campaigns do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :campaign_type, null: false, default: "other"
      t.string :status, null: false, default: "active"
      t.date :starts_on
      t.date :ends_on
      t.integer :budget_yen
      t.decimal :target_conversions, precision: 12, scale: 2
      t.integer :target_cpa_yen
      t.string :ga4_filter
      t.string :gsc_filter
      t.text :notes
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :business_campaigns, %i[business_id name], unique: true
    add_reference :business_prototypes, :business_campaign, foreign_key: true

    backfill_external_landing_pages
  end

  def down
    remove_reference :business_prototypes, :business_campaign, foreign_key: true
    drop_table :business_campaigns
  end

  private

  def backfill_external_landing_pages
    say_with_time "Assigning existing external landing pages to uncategorized campaigns" do
      MigrationBusiness.find_each do |business|
        landing_pages = MigrationPrototype.where(business_id: business.id)
          .where("metadata ->> 'role' IN (?)", %w[external_landing_page external_lp_integration])
        next unless landing_pages.exists?

        campaign = MigrationCampaign.find_or_create_by!(business_id: business.id, name: "未分類") do |record|
          record.campaign_type = "other"
          record.status = "active"
          record.metadata = { "backfilled" => true }
        end
        landing_pages.where(business_campaign_id: nil).update_all(business_campaign_id: campaign.id)
      end
    end
  end
end
