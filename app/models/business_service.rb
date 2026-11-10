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
    :admin_page_name,
    :other_page_name,
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
    [ user_page_configuration ] + additional_page_configurations
  end

  def user_page_configuration
    {
      id: "user",
      kind: "user",
      label: PAGE_LABELS.fetch("user"),
      name: PAGE_LABELS.fetch("user"),
      url: url,
      analysis_enabled: page_analysis_enabled?("user"),
      legacy: false
    }
  end

  def additional_page_configurations
    stored = stored_additional_pages.filter_map do |page|
      id = page["id"].to_s
      name = page["name"].to_s.strip
      page_url = page["url"].to_s.strip
      next if id.blank? || page_url.blank?

      {
        id:,
        kind: "other",
        label: name.presence || PAGE_LABELS.fetch("other"),
        name: name.presence || PAGE_LABELS.fetch("other"),
        url: page_url,
        analysis_enabled: ActiveModel::Type::Boolean.new.cast(page["analysis_enabled"]),
        legacy: false
      }
    end

    legacy = %w[admin other].filter_map do |kind|
      page_url = page_url(kind)
      next if page_url.blank?
      next if stored.any? { |page| page[:url] == page_url }

      configured_name = metadata.to_h["#{kind}_page_name"].to_s.strip
      {
        id: kind,
        kind: kind,
        label: configured_name.presence || PAGE_LABELS.fetch(kind),
        name: configured_name.presence || PAGE_LABELS.fetch(kind),
        url: page_url,
        analysis_enabled: page_analysis_enabled?(kind),
        legacy: true
      }
    end

    stored + legacy
  end

  def stored_additional_pages
    Array(metadata.to_h["additional_pages"]).filter_map do |page|
      page.to_h.deep_stringify_keys if page.respond_to?(:to_h)
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
