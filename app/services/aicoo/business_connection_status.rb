module Aicoo
  class BusinessConnectionStatus
    Result = Data.define(
      :source_key,
      :label,
      :configured,
      :enabled,
      :status_key,
      :status_label,
      :status_level,
      :setting_scope,
      :setting_label,
      :summary,
      :warning,
      :identifier,
      :credential,
      :setting,
      :latest_run,
      :latest_success_run,
      :last_fetched_at,
      :last_count,
      :last_error,
      :reauthentication_required
    ) do
      def configured? = configured
      def enabled? = enabled
      def uses_global? = setting_scope == "global"
      def individual? = setting_scope == "business"
      def missing? = status_key == "missing"
      def display_label = setting_label.present? ? "#{status_label}（#{setting_label}）" : status_label
    end

    SOURCE_LABELS = {
      "ga4" => "GA4",
      "gsc" => "GSC",
      "serp" => "SERP",
      "openai" => "OpenAI",
      "codex" => "Codex"
    }.freeze

    GOOGLE_SOURCE_KEYS = %w[ga4 gsc].freeze

    def initialize(business, source_key:, health: nil)
      @business = business
      @source_key = source_key.to_s
      @health = health
    end

    def call
      case source_key
      when "ga4", "gsc" then google_result
      when "serp" then serp_result
      when "openai" then openai_result
      when "codex" then codex_result
      else generic_data_source_result
      end
    end

    private

    attr_reader :business, :source_key, :health

    def base_result(**attributes)
      Result.new(
        source_key:,
        label: SOURCE_LABELS.fetch(source_key, source_key.upcase),
        configured: false,
        enabled: true,
        status_key: "missing",
        status_label: "未設定",
        status_level: "critical",
        setting_scope: "missing",
        setting_label: "未設定",
        summary: "設定がありません",
        warning: nil,
        identifier: nil,
        credential: nil,
        setting: nil,
        latest_run: nil,
        latest_success_run: nil,
        last_fetched_at: nil,
        last_count: 0,
        last_error: nil,
        reauthentication_required: false,
        **attributes
      )
    end

    def google_result
      return disabled_result(summary: "Business側で無効です") if business_data_source_setting&.enabled? == false

      selected_identifier = business_data_source_identifier.presence ||
        analytics_site_identifier.presence ||
        named_setting_identifier.presence ||
        business_gsc_site_url.presence
      selected_credential = google_credential
      selected_setting = analytics_source_setting
      reauthentication_required = google_reauthentication_required?(selected_credential)
      latest = latest_run(selected_setting)
      last_error = latest_failed_run(selected_setting)&.error_message

      if business_data_source_identifier.present?
        return base_result(
          configured: selected_credential&.connected? && !reauthentication_required,
          status_key: selected_credential&.connected? && !reauthentication_required ? "business" : "needs_attention",
          status_label: selected_credential&.connected? && !reauthentication_required ? "設定済み" : "再認証が必要",
          status_level: selected_credential&.connected? && !reauthentication_required ? "healthy" : "warning",
          setting_scope: "business",
          setting_label: "Business個別設定",
          summary: selected_identifier,
          warning: selected_credential.present? ? nil : "Google Credentialが未設定です",
          identifier: selected_identifier,
          credential: selected_credential,
          setting: selected_setting,
          latest_run: latest,
          latest_success_run: latest_success_run(selected_setting),
          last_fetched_at: latest&.finished_at || latest&.started_at || selected_setting&.last_fetched_at,
          last_count: latest&.snapshot_count.to_i,
          last_error:,
          reauthentication_required:
        )
      end

      if selected_identifier.present? && reauthentication_required
        return base_result(
          configured: false,
          status_key: "needs_attention",
          status_label: "再認証が必要",
          status_level: "warning",
          setting_scope: "global",
          setting_label: "全体設定を使用",
          summary: selected_identifier,
          warning: "Google再認証が必要です",
          identifier: selected_identifier,
          credential: selected_credential,
          setting: selected_setting,
          latest_run: latest,
          latest_success_run: latest_success_run(selected_setting),
          last_fetched_at: latest&.finished_at || latest&.started_at || selected_setting&.last_fetched_at,
          last_count: latest&.snapshot_count.to_i,
          last_error:,
          reauthentication_required:
        )
      end

      if global_google_available?
        return base_result(
          configured: true,
          status_key: "global",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "global",
          setting_label: "全体設定を使用",
          summary: selected_identifier.presence || "AICOO全体Google認証",
          identifier: selected_identifier,
          credential: selected_credential,
          setting: selected_setting,
          latest_run: latest,
          latest_success_run: latest_success_run(selected_setting),
          last_fetched_at: latest&.finished_at || latest&.started_at || selected_setting&.last_fetched_at,
          last_count: latest&.snapshot_count.to_i,
          last_error:,
          reauthentication_required:
        )
      end

      base_result(
        summary: selected_identifier.presence || "Google全体設定がありません",
        identifier: selected_identifier,
        credential: selected_credential,
        setting: selected_setting,
        last_error:,
        reauthentication_required:
      )
    end

    def serp_result
      profile = DataSourceCostProfile.for_source("serp")
      optional = Aicoo::Serp::OptionalMode.call
      active_query_count = business.serp_queries.where(enabled: true, status: "active").count
      active_keyword_count = business.business_serp_keywords.active.count

      return disabled_result(summary: "Business側でSERPがOFFです") unless business.serp_enabled?
      return disabled_result(summary: "SERP全体設定がOFFです") unless profile.enabled?

      if active_query_count.positive? || active_keyword_count.positive?
        return base_result(
          configured: optional.api_key_configured,
          status_key: optional.api_key_configured ? "business" : "needs_attention",
          status_label: optional.api_key_configured ? "設定済み" : "未設定",
          status_level: optional.api_key_configured ? "healthy" : "warning",
          setting_scope: "business",
          setting_label: "Business個別設定",
          summary: "検索クエリ #{active_query_count}件 / 承認済み #{active_keyword_count}件",
          warning: optional.api_key_configured ? nil : optional.message
        )
      end

      if optional.api_key_configured
        return base_result(
          configured: true,
          status_key: "global",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "global",
          setting_label: "全体設定を使用",
          summary: "Provider: #{optional.provider}"
        )
      end

      base_result(summary: optional.message, warning: optional.message)
    end

    def openai_result
      profile = DataSourceCostProfile.for_source("openai")
      return disabled_result(summary: "OpenAI全体設定がOFFです") unless profile.enabled?

      if profile.api_key_configured?
        base_result(
          configured: true,
          status_key: "global",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "global",
          setting_label: "全体設定を使用",
          summary: profile.api_key.present? ? "AICOO設定API Key" : "OPENAI_API_KEY"
        )
      else
        base_result(summary: "OPENAI_API_KEY未設定")
      end
    end

    def codex_result
      if business.aicoo_internal_codex?
        return base_result(
          configured: true,
          status_key: "aicoo_internal",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "business",
          setting_label: "Business個別設定",
          summary: "AICOO内部プロジェクト（接続済み）"
        )
      end

      profile = business.business_execution_profile
      if business.project_key.present? && business.local_project_path.present? && business.repository_name.present?
        return base_result(
          configured: true,
          status_key: "business",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "business",
          setting_label: "Business個別設定",
          summary: business.repository_name
        )
      end

      if profile&.coverage_status == "configured"
        return base_result(
          configured: true,
          status_key: "profile",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "business",
          setting_label: "Execution Profile",
          summary: profile.display_repository_name
        )
      end

      base_result(summary: "Execution Profile未設定")
    end

    def generic_data_source_result
      setting = business_data_source_setting
      profile = DataSourceCostProfile.for_source(source_key)
      return disabled_result(summary: "Business側で無効です") if setting&.enabled? == false
      return disabled_result(summary: "#{profile.name}全体設定がOFFです") unless profile.enabled?

      if setting&.linked?
        return base_result(
          configured: true,
          status_key: "business",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "business",
          setting_label: "Business個別設定",
          summary: setting.connection_summary
        )
      end

      if global_default_available_for?(profile)
        return base_result(
          configured: true,
          status_key: "global",
          status_label: "設定済み",
          status_level: "healthy",
          setting_scope: "global",
          setting_label: "全体設定を使用",
          summary: profile.name
        )
      end

      base_result(summary: setting&.connection_summary || "#{profile.name}未設定")
    end

    def disabled_result(summary:)
      base_result(
        enabled: false,
        status_key: "disabled",
        status_label: "無効",
        status_level: "attention",
        setting_scope: "disabled",
        setting_label: "無効",
        summary:
      )
    end

    def business_data_source_setting
      @business_data_source_setting ||= BusinessDataSourceSetting.find_by(business:, source_key:)
    end

    def business_data_source_identifier
      return unless GOOGLE_SOURCE_KEYS.include?(source_key)
      return unless business_data_source_setting&.enabled?

      key = source_key == "ga4" ? "property_id" : "site_url"
      business_data_source_setting.connection_field_value(key).presence ||
        business_data_source_setting.property_identifier.presence
    end

    def analytics_site
      @analytics_site ||= AicooAnalyticsSite.where(business:).recent.first
    end

    def analytics_site_identifier
      source_key == "ga4" ? analytics_site&.ga4_property_id.presence : analytics_site&.gsc_site_url.presence
    end

    def named_setting
      @named_setting ||= AnalyticsSourceSetting
        .where(source_type: source_key, enabled: true)
        .to_a
        .find { |row| row.name.to_s.match?(/\A#{Regexp.escape(business.name)}\b/i) }
    end

    def named_setting_identifier
      source_key == "ga4" ? named_setting&.property_id.presence : named_setting&.site_url.presence
    end

    def business_gsc_site_url
      business.gsc_site_url.presence if source_key == "gsc"
    end

    def analytics_source_setting
      @analytics_source_setting ||= AnalyticsSourceSetting.includes(:aicoo_analytics_site)
        .where(source_type: source_key, enabled: true)
        .find do |row|
          row.aicoo_analytics_site&.business_id == business.id ||
            identifier_matches?(row) ||
            row.id == named_setting&.id
        end
    end

    def identifier_matches?(row)
      identifier = business_data_source_identifier.presence ||
        analytics_site_identifier.presence ||
        named_setting_identifier.presence ||
        business_gsc_site_url.presence
      return false if identifier.blank?

      source_key == "ga4" ? row.property_id == identifier : row.site_url == identifier
    end

    def google_credential
      explicit_id = business_data_source_setting&.metadata.to_h["google_credential_id"]
      explicit_credential = AicooGoogleCredential.find_by(id: explicit_id) if explicit_id.present?
      return explicit_credential if explicit_credential
      return nil if business_data_source_identifier.present?

      analytics_source_setting&.google_credential || AicooGoogleCredential.default
    end

    def global_google_available?
      AicooGoogleCredential.default&.connected? || env_google_credentials_present?
    end

    def env_google_credentials_present?
      ENV["GOOGLE_CLIENT_ID"].present? &&
        ENV["GOOGLE_CLIENT_SECRET"].present? &&
        ENV["GOOGLE_REFRESH_TOKEN"].present?
    end

    def google_reauthentication_required?(credential)
      latest_failed_run(analytics_source_setting)&.error_message.to_s.match?(/invalid_grant|expired or revoked/i).present? ||
        credential&.reauthentication_required? ||
        credential&.token_expired? ||
        false
    end

    def latest_run(setting)
      setting&.analytics_fetch_runs&.recent&.first
    end

    def latest_success_run(setting)
      setting&.analytics_fetch_runs&.where(status: "success")&.recent&.first
    end

    def latest_failed_run(setting)
      setting&.analytics_fetch_runs&.where(status: "failed")&.recent&.first
    end

    def global_default_available_for?(profile)
      return false unless profile.enabled?
      fields = profile.credential_fields
      return true if fields.empty?

      fields.any? { |field| profile.credential_configured?(field.key) }
    end
  end
end
