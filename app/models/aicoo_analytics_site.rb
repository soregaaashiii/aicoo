class AicooAnalyticsSite < ApplicationRecord
  AUTHENTICATION_MODES = AnalyticsSourceSetting::AUTHENTICATION_MODES

  belongs_to :business, optional: true
  has_many :analytics_source_settings, dependent: :nullify
  has_many :data_imports, dependent: :nullify

  validates :name, presence: true
  validates :authentication_mode, inclusion: { in: AUTHENTICATION_MODES }

  after_save :sync_analytics_source_settings

  scope :recent, -> { order(created_at: :desc) }

  def gsc_setting
    analytics_source_settings.where(source_type: "gsc").order(created_at: :desc).first ||
      AnalyticsSourceSetting.where(source_type: "gsc", site_url: gsc_site_url).order(created_at: :desc).first
  end

  def ga4_setting
    analytics_source_settings.where(source_type: "ga4").order(created_at: :desc).first ||
      AnalyticsSourceSetting.where(source_type: "ga4", property_id: ga4_property_id).order(created_at: :desc).first
  end

  def gsc_status
    source_status(gsc_setting, gsc_site_url)
  end

  def ga4_status
    source_status(ga4_setting, ga4_property_id)
  end

  def google_credential_label
    return "個別Google認証" if individual_authentication?

    credential = [ gsc_setting, ga4_setting ].compact.map(&:effective_google_credential).compact.first ||
                 AicooGoogleCredential.default
    credential ? "共通Google認証" : "未設定"
  end

  def shared_authentication?
    authentication_mode == "shared"
  end

  def individual_authentication?
    authentication_mode == "individual"
  end

  def authentication_warning
    if individual_authentication? && [ gsc_setting, ga4_setting ].compact.none?(&:individual_credentials_present?)
      "このサイトは個別認証を使う設定ですが、認証情報が未設定です"
    elsif shared_authentication? && AicooGoogleCredential.default.blank?
      "AICOO共通Google認証が未接続です"
    end
  end

  def gsc_missing?
    gsc_site_url.blank?
  end

  def ga4_missing?
    ga4_property_id.blank?
  end

  def public_url_missing?
    public_url.blank?
  end

  private

  def sync_analytics_source_settings
    sync_gsc_setting if gsc_site_url.present?
    sync_ga4_setting if ga4_property_id.present?
  end

  def sync_gsc_setting
    setting = analytics_source_settings.find_by(source_type: "gsc") ||
              AnalyticsSourceSetting.find_by(source_type: "gsc", site_url: gsc_site_url) ||
              AnalyticsSourceSetting.new(source_type: "gsc")
    setting.assign_attributes(
      aicoo_analytics_site: self,
      name: "#{name} GSC",
      site_url: gsc_site_url,
      enabled: enabled,
      fetch_days: setting.fetch_days.presence || 28,
      authentication_mode:,
      google_credential: shared_authentication? ? (setting.google_credential || AicooGoogleCredential.default) : nil
    )
    setting.save!
  end

  def sync_ga4_setting
    setting = analytics_source_settings.find_by(source_type: "ga4") ||
              AnalyticsSourceSetting.find_by(source_type: "ga4", property_id: ga4_property_id) ||
              AnalyticsSourceSetting.new(source_type: "ga4")
    setting.assign_attributes(
      aicoo_analytics_site: self,
      name: "#{name} GA4",
      property_id: ga4_property_id,
      enabled: enabled,
      fetch_days: setting.fetch_days.presence || 28,
      authentication_mode:,
      google_credential: shared_authentication? ? (setting.google_credential || AicooGoogleCredential.default) : nil
    )
    setting.save!
  end

  def source_status(setting, identifier)
    return "未設定" if identifier.blank? || setting.blank? || !setting.enabled?

    case setting.latest_fetch_run&.status
    when "success"
      "最終取得成功"
    when "failed"
      "最終取得失敗"
    else
      "設定済み"
    end
  end
end
