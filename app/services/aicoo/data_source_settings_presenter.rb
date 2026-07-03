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
      :setting_label,
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
      status = Aicoo::SystemStatusResolver.call("codex", business:)
      CodexStatus.new(
        status_key: status.status.downcase,
        status_label: status.display_label,
        status_level: status.status_level,
        summary: status.reason
      )
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
      system_status = Aicoo::SystemStatusResolver.call(profile.source_key, business:)
      status = Aicoo::BusinessConnectionStatus.new(business, source_key: profile.source_key).call
      BusinessStatus.new(
        source_key: profile.source_key,
        name: profile.name,
        enabled: status.enabled?,
        status_key: system_status.status.downcase,
        status_label: system_status.display_label,
        status_level: system_status.status_level,
        global_status:,
        uses_global: status.uses_global?,
        setting_label: system_status.source.presence || status.setting_label,
        connection_summary: system_status.reason.presence || status.summary.presence || setting.connection_summary,
        execution_mode: source_binding(setting)["execution_mode"].presence || profile.execution_mode,
        monthly_budget_yen: source_binding(setting)["monthly_budget_yen"].presence || profile.monthly_budget_yen,
        last_sync_at: status.last_fetched_at || setting.last_connected_at || profile.last_run_at,
        manual_paid: manual_paid?(profile),
        warning: system_status.connected? ? nil : system_status.reason
      )
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

    def profile_for(source_key)
      profiles.find { |profile| profile.source_key == source_key }
    end
  end
end
