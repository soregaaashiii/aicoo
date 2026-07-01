module Aicoo
  class DataSourceSettingsPresenter
    GlobalStatus = Data.define(
      :source_key,
      :name,
      :section,
      :enabled,
      :status_key,
      :status_label,
      :status_level,
      :global_default_available,
      :execution_mode,
      :monthly_budget_yen,
      :monthly_spend_yen,
      :monthly_run_count,
      :last_sync_at,
      :credential_labels,
      :configured_credential_labels,
      :manual_paid
    )
    BusinessStatus = Data.define(
      :source_key,
      :name,
      :enabled,
      :status_key,
      :status_label,
      :status_level,
      :global_status,
      :uses_global,
      :connection_summary,
      :execution_mode,
      :monthly_budget_yen,
      :last_sync_at,
      :manual_paid,
      :warning
    )
    CodexStatus = Data.define(
      :status_key,
      :status_label,
      :status_level,
      :summary
    )

    SECTION_LABELS = {
      google: "Google",
      search: "Search / SEO",
      social: "Social",
      behavior: "Behavior",
      ads: "Ads",
      ai_development: "AI / Development",
      cost_engine: "Cost Engine",
      internal: "Internal"
    }.freeze

    SOURCE_SECTIONS = {
      "gsc" => :google,
      "ga4" => :google,
      "serp" => :search,
      "deep_research" => :search,
      "x" => :social,
      "youtube" => :social,
      "reddit" => :social,
      "clarity" => :behavior,
      "google_ads" => :ads,
      "meta_ads" => :ads,
      "openai" => :ai_development,
      "github" => :ai_development,
      "product_hunt" => :social,
      "explore" => :internal,
      "opportunity_scan" => :internal,
      "learning" => :internal,
      "revenue" => :internal,
      "business_metric_daily" => :internal
    }.freeze

    COMPACT_BUSINESS_SOURCES = %w[gsc ga4 serp x youtube clarity google_ads meta_ads openai].freeze

    def initialize(profiles: DataSourceCostProfile.ordered, settings: BusinessDataSourceSetting.all)
      @profiles = profiles.to_a
      @settings = settings.to_a
      @settings_by_business_and_source = @settings.index_by { |setting| [ setting.business_id, setting.source_key ] }
    end

    def global_statuses
      @global_statuses ||= profiles.map { |profile| build_global_status(profile) }
    end

    def global_statuses_by_section
      global_statuses.group_by(&:section)
    end

    def section_label(section)
      SECTION_LABELS.fetch(section, section.to_s.humanize)
    end

    def business_statuses(business, source_keys: COMPACT_BUSINESS_SOURCES)
      source_keys.filter_map do |source_key|
        profile = profile_for(source_key)
        next unless profile

        build_business_status(business, profile)
      end
    end

    def business_status(business, source_key)
      profile = profile_for(source_key)
      return unless profile

      build_business_status(business, profile)
    end

    def codex_status(business)
      if business.aicoo_internal_codex?
        return CodexStatus.new(
          status_key: "aicoo_internal",
          status_label: "🟢 AICOO内部プロジェクト（接続済み）",
          status_level: "healthy",
          summary: "AICOO本体Repositoryを使用"
        )
      end

      configured = business.project_key.present? &&
        business.local_project_path.present? &&
        business.repository_name.present?
      profile = business.business_execution_profile
      if configured
        CodexStatus.new(
          status_key: "individual",
          status_label: "✅ 個別設定済み",
          status_level: "healthy",
          summary: business.repository_name
        )
      elsif profile&.coverage_status == "configured"
        CodexStatus.new(
          status_key: "profile",
          status_label: "🟢 Execution Profile使用",
          status_level: "healthy",
          summary: profile.display_repository_name
        )
      else
        CodexStatus.new(
          status_key: "missing",
          status_label: "🔴 未設定",
          status_level: "critical",
          summary: "project_key / path / repository未設定"
        )
      end
    end

    private

    attr_reader :profiles, :settings_by_business_and_source

    def build_global_status(profile)
      credential_fields = profile.credential_fields
      configured_labels = credential_fields.select { |field| profile.credential_configured?(field.key) }.map(&:label)
      global_default_available = global_default_available_for?(profile, credential_fields, configured_labels)
      status_key, status_label, status_level = global_status_tuple(profile, credential_fields, configured_labels)

      GlobalStatus.new(
        source_key: profile.source_key,
        name: profile.name,
        section: SOURCE_SECTIONS.fetch(profile.source_key, :internal),
        enabled: profile.enabled?,
        status_key:,
        status_label:,
        status_level:,
        global_default_available:,
        execution_mode: profile.execution_mode,
        monthly_budget_yen: profile.monthly_budget_yen,
        monthly_spend_yen: profile.monthly_spend_yen,
        monthly_run_count: profile.monthly_run_count,
        last_sync_at: profile.last_run_at,
        credential_labels: credential_fields.map(&:label),
        configured_credential_labels: configured_labels,
        manual_paid: manual_paid?(profile)
      )
    end

    def global_status_tuple(profile, credential_fields, configured_labels)
      return [ "disabled", "無効", "attention" ] unless profile.enabled?
      return [ "error", "🔴 エラー", "critical" ] if profile.last_error.present?
      return [ "connected", "✅ Connected", "healthy" ] if global_default_available_for?(profile, credential_fields, configured_labels)

      [ "not_configured", "🔴 Not configured", "critical" ]
    end

    def build_business_status(business, profile)
      setting = settings_by_business_and_source[[ business.id, profile.source_key ]] ||
        BusinessDataSourceSetting.new(business:, source_key: profile.source_key)
      global_status = build_global_status(profile)
      uses_global = use_global?(setting)
      google_identifier = google_business_identifier(business, profile.source_key, setting)
      status_key, status_label, status_level = business_status_tuple(setting, global_status, uses_global, google_identifier:)
      BusinessStatus.new(
        source_key: profile.source_key,
        name: profile.name,
        enabled: setting.enabled?,
        status_key:,
        status_label:,
        status_level:,
        global_status:,
        uses_global:,
        connection_summary: google_identifier.presence || setting.connection_summary,
        execution_mode: source_binding(setting)["execution_mode"].presence || profile.execution_mode,
        monthly_budget_yen: source_binding(setting)["monthly_budget_yen"].presence || profile.monthly_budget_yen,
        last_sync_at: setting.last_connected_at || profile.last_run_at,
        manual_paid: manual_paid?(profile),
        warning: business_warning(setting, global_status, uses_global, google_identifier:)
      )
    end

    def business_status_tuple(setting, global_status, uses_global, google_identifier: nil)
      return [ "disabled", "無効", "attention" ] unless setting.enabled?
      return [ "error", "🔴 エラー", "critical" ] if setting.connection_status == "error"
      if setting.linked?
        return [ "individual", "✅ 個別設定済み", "healthy" ]
      end
      if google_identifier.present? && uses_global && global_status.global_default_available
        return [ "global", "🟢 全体設定使用", "healthy" ]
      end
      if setting.connection_status == "needs_attention"
        return [ "needs_attention", "⚠ 設定済みだが未同期", "warning" ]
      end
      if uses_global && global_status.global_default_available
        return [ "global", "🟢 全体設定使用", "healthy" ]
      end
      if setting_present?(setting)
        return [ "needs_attention", "⚠ 設定済みだが未同期", "warning" ]
      end

      [ "missing", "🔴 未設定", "critical" ]
    end

    def business_warning(setting, global_status, uses_global, google_identifier: nil)
      return "Business側で無効です" unless setting.enabled?
      return setting.notes.presence || "接続エラーを確認してください" if setting.connection_status == "error"
      return "AICOO全体設定の認証情報が未設定です" if uses_global && !global_status.global_default_available
      return "設定済みですが同期成功がまだありません" if google_identifier.present? && setting.connection_status == "needs_attention"
      return "Business固有のProperty / Account / Keywordが未設定です" if setting.connection_status == "unlinked" && !uses_global
      return "設定済みですが同期成功がまだありません" if setting.connection_status == "needs_attention"

      nil
    end

    def setting_present?(setting)
      setting.property_identifier.present? ||
        setting.external_account_id.present? ||
        setting.endpoint_url.present? ||
        setting.credential_reference.present? ||
        setting.connection_field_values.values.any?(&:present?)
    end

    def use_global?(setting)
      ActiveModel::Type::Boolean.new.cast(source_binding(setting).fetch("use_global", true))
    end

    def source_binding(setting)
      setting.metadata.to_h.fetch("source_binding", {})
    end

    def manual_paid?(profile)
      profile.execution_mode == "manual" && profile.average_cost_yen.to_d.positive?
    end

    def global_default_available_for?(profile, credential_fields, configured_labels)
      return false unless profile.enabled?
      return true if credential_fields.empty? || configured_labels.any?
      return true if profile.source_key.in?(%w[gsc ga4]) && AicooGoogleCredential.default&.connected?

      false
    end

    def google_business_identifier(business, source_key, setting)
      return unless source_key.in?(%w[gsc ga4])

      key = source_key == "gsc" ? "site_url" : "property_id"
      setting.connection_field_value(key).presence ||
        setting.property_identifier.presence ||
        analytics_site_identifier(business, source_key) ||
        named_analytics_setting_identifier(business, source_key) ||
        (business.gsc_site_url.presence if source_key == "gsc")
    end

    def analytics_site_identifier(business, source_key)
      site = AicooAnalyticsSite.where(business:).recent.first
      source_key == "gsc" ? site&.gsc_site_url.presence : site&.ga4_property_id.presence
    end

    def named_analytics_setting_identifier(business, source_key)
      return unless source_key.in?(%w[gsc ga4])

      setting = AnalyticsSourceSetting
        .where(source_type: source_key, enabled: true)
        .to_a
        .find { |row| row.name.to_s.match?(/\A#{Regexp.escape(business.name)}\b/i) }
      source_key == "gsc" ? setting&.site_url.presence : setting&.property_id.presence
    end

    def profile_for(source_key)
      profiles.find { |profile| profile.source_key == source_key }
    end
  end
end
