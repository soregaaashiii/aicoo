module AicooAnalytics
  class ScheduleReadinessChecker
    Check = Data.define(:name, :status, :message)
    Result = Data.define(:ready, :checks)

    def call
      checks = [
        enabled_settings_check,
        *setting_checks,
        credentials_check,
        latest_success_check,
        latest_data_import_check,
        latest_snapshot_check
      ].compact

      Result.new(ready: checks.none? { |check| check.status == "error" }, checks:)
    end

    private

    def enabled_settings
      @enabled_settings ||= AnalyticsSourceSetting.where(enabled: true).to_a
    end

    def latest_success_run
      @latest_success_run ||= AnalyticsFetchRun.where(status: "success").recent.first
    end

    def enabled_settings_check
      return ok("有効な設定", "有効なAnalytics設定があります") if enabled_settings.any?

      error("有効な設定", "有効なAnalytics設定がありません")
    end

    def setting_checks
      enabled_settings.flat_map do |setting|
        [
          source_type_check(setting),
          ga4_property_check(setting),
          gsc_site_url_check(setting),
          authentication_mode_check(setting)
        ].compact
      end
    end

    def source_type_check(setting)
      return ok("#{setting.name} source_type", "#{setting.source_type.upcase}設定です") if setting.source_type.in?(AnalyticsSourceSetting::SOURCE_TYPES)

      error("#{setting.name} source_type", "source_typeがga4/gscではありません")
    end

    def ga4_property_check(setting)
      return unless setting.source_type == "ga4"
      return ok("#{setting.name} property_id", "GA4 property_id が設定されています") if setting.property_id.present?

      error("#{setting.name} property_id", "GA4設定にproperty_idがありません")
    end

    def gsc_site_url_check(setting)
      return unless setting.source_type == "gsc"
      return ok("#{setting.name} site_url", "GSC site_url が設定されています") if setting.site_url.present?

      error("#{setting.name} site_url", "GSC設定にsite_urlがありません")
    end

    def authentication_mode_check(setting)
      if setting.individual_authentication? && !setting.individual_credentials_present?
        warning("#{setting.name} 認証方式", "この設定は個別認証ですが、個別認証情報が未設定です")
      elsif setting.shared_authentication? && AicooGoogleCredential.default.blank?
        warning("#{setting.name} 認証方式", "AICOO共通Google認証が未接続です")
      else
        ok("#{setting.name} 認証方式", setting.shared_authentication? ? "共通認証を使います" : "個別認証を使います")
      end
    end

    def credentials_check
      return ok("認証情報", "認証情報が設定されています") if credentials_present?

      error("認証情報", "共通Google認証、個別認証、またはGOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKENが不足しています")
    end

    def credentials_present?
      setting_credentials_present? || google_credential_present? || env_credentials_present?
    end

    def setting_credentials_present?
      enabled_settings.any? do |setting|
        if setting.individual_authentication?
          setting.individual_credentials_present?
        else
          setting.effective_google_credential.present?
        end
      end
    end

    def google_credential_present?
      AicooGoogleCredential.default.present?
    end

    def env_credentials_present?
      ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present? && ENV["GOOGLE_REFRESH_TOKEN"].present?
    end

    def latest_success_check
      return ok("直近取得", "直近のAnalytics取得がsuccessしています") if latest_success_run

      warning("直近取得", "直近取得がまだありません")
    end

    def latest_data_import_check
      return warning("DataImport", "直近success取得がまだないためDataImportを確認できません") unless latest_success_run
      return ok("DataImport", "直近取得でDataImportが作られています") if latest_success_run.data_import_id.present?

      error("DataImport", "直近取得でDataImportが作られていません")
    end

    def latest_snapshot_check
      return warning("Snapshot", "直近success取得がまだないためSnapshotを確認できません") unless latest_success_run
      return ok("Snapshot", "直近取得でSnapshotが作られています") if latest_success_run.snapshot_count.to_i.positive?

      error("Snapshot", "直近取得でSnapshotが作られていません")
    end

    def ok(name, message)
      Check.new(name:, status: "ok", message:)
    end

    def warning(name, message)
      Check.new(name:, status: "warning", message:)
    end

    def error(name, message)
      Check.new(name:, status: "error", message:)
    end
  end
end
