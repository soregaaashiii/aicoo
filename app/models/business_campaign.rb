class BusinessCampaign < ApplicationRecord
  CAMPAIGN_TYPES = %w[seo google_ads meta_ads comparison sns email referral other].freeze
  STATUSES = %w[draft active paused completed archived].freeze

  belongs_to :business
  has_many :landing_pages,
    -> { external_landing_pages },
    class_name: "BusinessPrototype",
    dependent: :nullify,
    inverse_of: :business_campaign

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :campaign_type, inclusion: { in: CAMPAIGN_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :budget_yen, :target_cpa_yen, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :target_conversions, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :date_range_is_valid

  scope :active, -> { where.not(status: "archived") }
  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  def campaign_type_label
    {
      "seo" => "SEO",
      "google_ads" => "Google Ads",
      "meta_ads" => "Meta Ads",
      "comparison" => "比較",
      "sns" => "SNS",
      "email" => "メール",
      "referral" => "紹介",
      "other" => "その他"
    }.fetch(campaign_type, campaign_type)
  end

  def status_label
    {
      "draft" => "下書き",
      "active" => "運用中",
      "paused" => "停止中",
      "completed" => "完了",
      "archived" => "アーカイブ"
    }.fetch(status, status)
  end

  private

  def date_range_is_valid
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, "は開始日以降にしてください")
  end
end
