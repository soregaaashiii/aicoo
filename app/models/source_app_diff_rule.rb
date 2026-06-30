class SourceAppDiffRule < ApplicationRecord
  belongs_to :source_app_connection
  has_one :source_app_diff_cursor, dependent: :destroy

  validates :name, :watched_table, :resource_type, :activity_type, presence: true
  validates :name, uniqueness: { scope: :source_app_connection_id }
  validates :estimated_work_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :enabled, -> { where(enabled: true).order(:priority, :id) }

  def cursor
    source_app_diff_cursor || create_source_app_diff_cursor!
  end

  def self.ensure_suelog_defaults!(connection)
    SUELOG_DEFAULTS.each do |attributes|
      find_or_initialize_by(source_app_connection: connection, name: attributes[:name]).tap do |rule|
        rule.assign_attributes(attributes)
        rule.save!
      end
    end
  end

  SUELOG_DEFAULTS = [
    {
      name: "Shop作成",
      watched_table: "shops",
      resource_type: "Shop",
      activity_type: "shop_created",
      watched_fields: %w[name area smoking_status station source tabelog_url created_at updated_at],
      metadata_fields: %w[area smoking_status station source tabelog_url],
      title_template: "店舗を追加: %{name}",
      estimated_work_seconds: 20,
      priority: 10
    },
    {
      name: "Shopプロフィール更新",
      watched_table: "shops",
      resource_type: "Shop",
      activity_type: "shop_profile_updated",
      watched_fields: %w[smoking_status address phone business_hours closed_days status updated_at],
      metadata_fields: %w[area smoking_status station status],
      title_template: "Shopを更新: %{name}",
      estimated_work_seconds: 30,
      priority: 20
    },
    {
      name: "記事作成/更新",
      watched_table: "articles",
      resource_type: "Article",
      activity_type: "article_updated",
      watched_fields: %w[title slug seo_title meta_description status area target_keyword published_at updated_at],
      metadata_fields: %w[slug area target_keyword status],
      title_template: "記事を更新: %{title}",
      estimated_work_seconds: 180,
      priority: 30
    }
  ].freeze
end
