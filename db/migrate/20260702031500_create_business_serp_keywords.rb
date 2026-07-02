class CreateBusinessSerpKeywords < ActiveRecord::Migration[8.1]
  class MigrationBusinessDataSourceSetting < ActiveRecord::Base
    self.table_name = "business_data_source_settings"
  end

  class MigrationBusinessSerpKeyword < ActiveRecord::Base
    self.table_name = "business_serp_keywords"
  end

  def up
    create_table :business_serp_keywords do |t|
      t.references :business, null: false, foreign_key: true
      t.string :keyword, null: false
      t.string :normalized_keyword, null: false
      t.string :source, null: false, default: "manual"
      t.string :status, null: false, default: "pending"
      t.integer :priority_score, null: false, default: 50
      t.integer :opportunity_score
      t.integer :confidence
      t.text :reason
      t.string :search_intent
      t.datetime :last_checked_at
      t.integer :check_count, null: false, default: 0
      t.integer :latest_rank
      t.decimal :latest_ctr, precision: 10, scale: 4
      t.integer :latest_clicks
      t.integer :latest_impressions
      t.jsonb :metadata_json, null: false, default: {}

      t.timestamps
    end

    add_index :business_serp_keywords, [ :business_id, :normalized_keyword ], unique: true, name: "index_business_serp_keywords_on_business_and_keyword"
    add_index :business_serp_keywords, [ :business_id, :status ]
    add_index :business_serp_keywords, :source
    add_index :business_serp_keywords, :priority_score
    add_index :business_serp_keywords, :last_checked_at

    backfill_legacy_serp_keywords
  end

  def down
    drop_table :business_serp_keywords
  end

  private

  def backfill_legacy_serp_keywords
    MigrationBusinessDataSourceSetting.where(source_key: "serp").find_each do |setting|
      legacy_keywords_for(setting).each do |keyword|
        normalized = normalize(keyword)
        next if normalized.blank?

        MigrationBusinessSerpKeyword.find_or_create_by!(
          business_id: setting.business_id,
          normalized_keyword: normalized
        ) do |row|
          row.keyword = keyword
          row.source = "imported"
          row.status = "active"
          row.priority_score = 60
          row.confidence = 60
          row.reason = "既存Business SERP設定から移行"
          row.metadata_json = { "backfilled_from" => "business_data_source_settings", "business_data_source_setting_id" => setting.id }
        end
      end
    end
  end

  def legacy_keywords_for(setting)
    fields = setting.metadata.to_h.fetch("connection_fields", {})
    [
      fields["keyword"],
      setting.property_identifier
    ].compact.join("\n").split(/[\n,、]/).map(&:strip).compact_blank
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkc).strip.downcase.gsub(/\s+/, " ")
  end
end
