class BusinessService < ApplicationRecord
  STATUSES = %w[planning building live production paused archived].freeze
  PAGE_KINDS = %w[user admin other].freeze
  PAGE_LABELS = {
    "user" => "ユーザーページ",
    "admin" => "管理者ページ",
    "other" => "その他ページ"
  }.freeze

  belongs_to :business

  store_accessor :metadata,
    :admin_url,
    :other_url,
    :user_page_analysis_enabled,
    :admin_page_analysis_enabled,
    :other_page_analysis_enabled

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(updated_at: :desc, created_at: :desc) }

  def display_url
    url.presence || domain.presence || "-"
  end

  def page_configurations
    PAGE_KINDS.map do |kind|
      {
        kind:,
        label: PAGE_LABELS.fetch(kind),
        url: page_url(kind),
        analysis_enabled: page_analysis_enabled?(kind)
      }
    end
  end

  def analysis_target_pages
    page_configurations.select { |page| page[:url].present? && page[:analysis_enabled] }
  end

  def analysis_target_urls
    analysis_target_pages.pluck(:url)
  end

  def page_url(kind)
    case kind.to_s
    when "user" then url
    when "admin" then admin_url
    when "other" then other_url
    else raise ArgumentError, "不明なページ種別です。"
    end
  end

  def page_analysis_enabled?(kind)
    kind = kind.to_s
    raise ArgumentError, "不明なページ種別です。" unless kind.in?(PAGE_KINDS)
    return false if page_url(kind).blank?

    key = "#{kind}_page_analysis_enabled"
    return kind == "user" unless metadata.to_h.key?(key)

    ActiveModel::Type::Boolean.new.cast(metadata.to_h[key])
  end
end
