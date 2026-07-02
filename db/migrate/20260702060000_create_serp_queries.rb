class CreateSerpQueries < ActiveRecord::Migration[8.1]
  class MigrationBusinessDataSourceSetting < ActiveRecord::Base
    self.table_name = "business_data_source_settings"
  end

  class MigrationBusinessSerpKeyword < ActiveRecord::Base
    self.table_name = "business_serp_keywords"
  end

  class MigrationSerpQuery < ActiveRecord::Base
    self.table_name = "serp_queries"
  end

  def up
    create_table :serp_queries do |t|
      t.references :business, null: false, foreign_key: true
      t.string :query, null: false
      t.string :normalized_query, null: false
      t.string :category, null: false, default: "existing_business"
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 100
      t.string :country, null: false, default: "jp"
      t.string :language, null: false, default: "ja"
      t.integer :daily_limit, null: false, default: 1
      t.datetime :last_run_at
      t.datetime :last_success_at
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.integer :total_candidates_generated, null: false, default: 0
      t.integer :total_candidates_approved, null: false, default: 0
      t.integer :total_revenue_yen, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :serp_queries, :enabled
    add_index :serp_queries, :priority
    add_index :serp_queries, [ :business_id, :normalized_query ], unique: true, name: "index_serp_queries_on_business_and_query"
    add_index :serp_queries, [ :business_id, :enabled, :priority ]
    add_index :serp_queries, :category

    backfill_serp_queries
  end

  def down
    drop_table :serp_queries
  end

  private

  def backfill_serp_queries
    backfill_from_business_serp_keywords
    backfill_from_business_data_source_settings
  end

  def backfill_from_business_serp_keywords
    return unless table_exists?(:business_serp_keywords)

    MigrationBusinessSerpKeyword.where(status: "active").find_each do |keyword|
      upsert_query!(
        business_id: keyword.business_id,
        query: keyword.keyword,
        priority: keyword.priority_score.presence || 100,
        category: "existing_business",
        source: "business_serp_keywords",
        source_id: keyword.id
      )
    end
  end

  def backfill_from_business_data_source_settings
    MigrationBusinessDataSourceSetting.where(source_key: "serp").find_each do |setting|
      legacy_keywords_for(setting).each do |query|
        upsert_query!(
          business_id: setting.business_id,
          query:,
          priority: 100,
          category: "existing_business",
          source: "business_data_source_settings",
          source_id: setting.id
        )
      end
    end
  end

  def upsert_query!(business_id:, query:, priority:, category:, source:, source_id:)
    normalized = normalize(query)
    return if normalized.blank?

    MigrationSerpQuery.find_or_create_by!(
      business_id:,
      normalized_query: normalized
    ) do |row|
      row.query = query.to_s.strip
      row.category = category
      row.enabled = true
      row.priority = priority.to_i
      row.country = "jp"
      row.language = "ja"
      row.daily_limit = 1
      row.metadata = { "backfilled_from" => source, "source_id" => source_id }
    end
  end

  def legacy_keywords_for(setting)
    fields = setting.metadata.to_h.fetch("connection_fields", {})
    [
      fields["keyword"],
      fields["monitored_keywords"],
      setting.property_identifier
    ].compact.join("\n").split(/[\n,、]/).map(&:strip).compact_blank
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkc).strip.downcase.gsub(/\s+/, " ")
  end
end
