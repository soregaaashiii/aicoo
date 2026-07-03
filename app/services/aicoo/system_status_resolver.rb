module Aicoo
  class SystemStatusResolver
    STATUSES = %w[CONNECTED WARNING BROKEN NOT_CONFIGURED].freeze

    Status = Data.define(
      :key,
      :label,
      :status,
      :reason,
      :next_action,
      :detail_url,
      :source,
      :metadata
    ) do
      def connected? = status == "CONNECTED"
      def warning? = status == "WARNING"
      def broken? = status == "BROKEN"
      def not_configured? = status == "NOT_CONFIGURED"

      def status_label
        case status
        when "CONNECTED" then "設定済み"
        when "WARNING" then "要確認"
        when "BROKEN" then "停止"
        else "未設定"
        end
      end

      def status_level
        case status
        when "CONNECTED" then "healthy"
        when "WARNING" then "warning"
        when "BROKEN" then "critical"
        else "critical"
        end
      end

      def display_label
        suffix = source.presence || reason
        suffix.present? ? "#{status_label}（#{suffix}）" : status_label
      end
    end

    include Rails.application.routes.url_helpers

    def self.call(...)
      new.call(...)
    end

    def call(key, business: nil)
      case key.to_s
      when "ga4", "gsc", "serp", "openai", "codex"
        business ? business_source_status(business, key.to_s) : global_source_status(key.to_s)
      when "daily_run"
        daily_run_status
      when "traffic"
        traffic_status
      when "traffic_serp"
        traffic_serp_status
      when "render"
        render_status
      when "pipeline"
        pipeline_status(business)
      when "learning"
        learning_status
      when "business_health"
        business_health_status(business)
      else
        business ? business_source_status(business, key.to_s) : global_source_status(key.to_s)
      end
    end

    private

    def build_status(key:, label:, status:, reason:, next_action: nil, detail_url: nil, source: nil, metadata: {})
      normalized = STATUSES.include?(status.to_s) ? status.to_s : "WARNING"
      Status.new(
        key:,
        label:,
        status: normalized,
        reason: reason.presence || "詳細理由なし",
        next_action: next_action.presence,
        detail_url: detail_url.presence,
        source: source.presence,
        metadata: metadata.to_h
      )
    end

    def business_source_status(business, source_key)
      raw = Aicoo::BusinessConnectionStatus.new(business, source_key:).call
      build_status(
        key: source_key,
        label: raw.label,
        status: normalize_connection(raw),
        reason: connection_reason(raw),
        next_action: next_action_for(source_key, raw),
        detail_url: detail_url_for(source_key, business),
        source: raw.setting_label,
        metadata: {
          configured: raw.configured?,
          enabled: raw.enabled?,
          status_key: raw.status_key,
          status_level: raw.status_level,
          setting_scope: raw.setting_scope,
          setting_label: raw.setting_label,
          summary: raw.summary,
          identifier: raw.identifier,
          credential_id: raw.credential&.id,
          credential_name: raw.credential&.name,
          property_id: source_key == "ga4" ? raw.identifier : nil,
          site_url: source_key == "gsc" ? raw.identifier : nil,
          last_fetched_at: raw.last_fetched_at,
          last_count: raw.last_count,
          last_error: raw.last_error,
          reauthentication_required: raw.reauthentication_required
        }
      )
    end

    def global_source_status(source_key)
      profile = DataSourceCostProfile.for_source(source_key)
      return build_status(key: source_key, label: label_for(source_key), status: "WARNING", reason: "#{profile.name}全体設定がOFFです。", detail_url: global_detail_url(source_key), source: "global") unless profile.enabled?

      configured = if source_key.in?(%w[ga4 gsc])
        credential_usable?(AicooGoogleCredential.default) || env_google_credentials_present?
      elsif source_key == "serp"
        Aicoo::Serp::OptionalMode.call.api_key_configured
      else
        profile.credential_fields.empty? || profile.credential_fields.any? { |field| profile.credential_configured?(field.key) }
      end

      build_status(
        key: source_key,
        label: label_for(source_key),
        status: configured ? "CONNECTED" : "NOT_CONFIGURED",
        reason: configured ? "全体設定が利用可能です。" : "#{profile.name}全体設定が未設定です。",
        next_action: configured ? nil : "全体設定を開く",
        detail_url: global_detail_url(source_key),
        source: "global",
        metadata: { profile_id: profile.id, profile_enabled: profile.enabled? }
      )
    end

    def normalize_connection(raw)
      return "WARNING" unless raw.enabled?
      return "BROKEN" if raw.reauthentication_required || raw.last_error.present?
      return "CONNECTED" if raw.configured? && raw.warning.blank?
      return "WARNING" if raw.warning.present? || raw.status_key == "needs_attention"

      "NOT_CONFIGURED"
    end

    def connection_reason(raw)
      return raw.warning if raw.warning.present?
      return raw.last_error if raw.last_error.present?
      return raw.summary if raw.configured? && raw.warning.blank?
      return "#{raw.label}は無効です。" unless raw.enabled?

      raw.summary
    end

    def next_action_for(source_key, raw)
      return "Google再認証" if source_key.in?(%w[ga4 gsc]) && raw.reauthentication_required
      return nil if raw.configured? && raw.warning.blank? && raw.last_error.blank?
      return "Business設定を開く" if source_key.in?(%w[ga4 gsc serp])
      return "Codex接続を開く" if source_key == "codex"

      "設定を確認"
    end

    def detail_url_for(source_key, business)
      case source_key
      when "ga4", "gsc"
        google_settings_business_path(business)
      when "serp"
        admin_serp_settings_path(business_id: business.id)
      when "codex"
        admin_codex_connection_path(business_id: business.id)
      when "openai"
        aicoo_setting_path
      end
    end

    def daily_run_status
      execution = Aicoo::DailyRunExecutionStatus.call
      latest = execution.latest_run
      if execution.running?
        return build_status(
          key: "daily_run",
          label: "Daily Run",
          status: execution.rows.any?(&:stuck?) ? "WARNING" : "CONNECTED",
          reason: execution.status_label,
          next_action: execution.rows.any?(&:stuck?) ? "Daily Run詳細を確認" : nil,
          detail_url: aicoo_daily_runs_path,
          source: "AicooDailyRun",
          metadata: { running_count: execution.rows.size, latest_run_id: latest&.id }
        )
      end

      status = if latest.blank?
        "NOT_CONFIGURED"
      elsif latest.succeeded?
        "CONNECTED"
      elsif latest.status == "partial_failed"
        "WARNING"
      else
        "BROKEN"
      end

      build_status(
        key: "daily_run",
        label: "Daily Run",
        status:,
        reason: latest ? "最終Run: #{latest.status}" : "Daily Run履歴がありません。",
        next_action: status == "CONNECTED" ? nil : "Daily Run Healthを確認",
        detail_url: latest ? aicoo_daily_run_path(latest) : aicoo_daily_runs_path,
        source: "AicooDailyRun",
        metadata: { latest_run_id: latest&.id, latest_status: latest&.status }
      )
    end

    def traffic_status
      summary = Aicoo::TrafficChannels::Summary.call
      build_status(
        key: "traffic",
        label: "Traffic",
        status: normalize_health(summary.health),
        reason: "止まっているチャネル #{summary.stopped_channel_count}件 / 今日稼働 #{summary.today_active_channel_count}件",
        next_action: summary.health == "Healthy" ? nil : "Traffic Channel Centerを開く",
        detail_url: admin_traffic_channels_path,
        source: "TrafficChannels::Summary",
        metadata: summary.to_h
      )
    end

    def traffic_serp_status
      summary = Aicoo::Serp::Summary.call
      build_status(
        key: "traffic_serp",
        label: "SERP",
        status: normalize_health(summary.health),
        reason: "今日 #{summary.today_query_count}件 / 成功 #{summary.today_success_query_count}件 / 失敗 #{summary.today_failed_query_count}件",
        next_action: summary.health == "Healthy" ? nil : "SERP設定を開く",
        detail_url: admin_serp_settings_path,
        source: "SerpRun",
        metadata: summary.to_h
      )
    end

    def render_status
      cron = Aicoo::DailyRunCronStatus.new.call
      enabled = ENV["AICOO_DAILY_RUN_ENABLED"] == "true"
      build_status(
        key: "render",
        label: "Render",
        status: enabled ? "CONNECTED" : "WARNING",
        reason: enabled ? "Cron実行可能です。" : "Cron ENVが未設定のため手動運用です。",
        next_action: enabled ? nil : "Render Cron設定を確認",
        detail_url: admin_cron_health_path,
        source: "ENV",
        metadata: cron.respond_to?(:to_h) ? cron.to_h : { cron_enabled: enabled }
      )
    end

    def pipeline_status(business)
      return build_status(key: "pipeline", label: "Pipeline", status: "NOT_CONFIGURED", reason: "Business未選択です。", detail_url: admin_pipeline_e2e_check_path) unless business

      run = AicooPipelineRun.where(business:).recent.first
      status = if run.blank?
        "NOT_CONFIGURED"
      elsif run.stuck?
        "WARNING"
      elsif run.status.in?(%w[failed blocked])
        "BROKEN"
      else
        "CONNECTED"
      end

      build_status(
        key: "pipeline",
        label: "Pipeline",
        status:,
        reason: run ? "Stage: #{run.current_stage} / #{run.status}" : "PipelineRunがありません。",
        next_action: status == "CONNECTED" ? nil : "Pipeline詳細を確認",
        detail_url: run ? admin_pipeline_e2e_check_path(business_id: business.id) : admin_pipeline_e2e_check_path,
        source: "AicooPipelineRun",
        metadata: { pipeline_run_id: run&.id, current_stage: run&.current_stage }
      )
    end

    def learning_status
      health = LearningLoopHealthSummary.new.call
      raw_status = health.health_status.to_s
      status = case raw_status
      when "healthy"
        "CONNECTED"
      when "critical"
        "BROKEN"
      when "warning", "attention"
        "WARNING"
      else
        "NOT_CONFIGURED"
      end
      build_status(
        key: "learning",
        label: "Learning",
        status:,
        reason: health.health_message.to_s.presence || "Learning状態を確認してください。",
        next_action: status == "CONNECTED" ? nil : "Learningを確認",
        detail_url: owner_learning_report_path,
        source: "LearningLoopHealthSummary",
        metadata: health.respond_to?(:to_h) ? health.to_h : {}
      )
    end

    def business_health_status(business)
      return build_status(key: "business_health", label: "Business Health", status: "NOT_CONFIGURED", reason: "Business未選択です。") unless business

      row = Aicoo::BusinessIntegrationHealth.new.call.business_healths.find { |health| health.business == business }
      status = if row.blank?
        "NOT_CONFIGURED"
      elsif row.health_score.to_d >= 80
        "CONNECTED"
      elsif row.health_score.to_d >= 60
        "WARNING"
      else
        "BROKEN"
      end

      build_status(
        key: "business_health",
        label: "Business Health",
        status:,
        reason: row ? "Health #{row.health_score} / warning #{row.warning_count}件" : "Business Health未計算です。",
        next_action: status == "CONNECTED" ? nil : "Business詳細を確認",
        detail_url: business_path(business),
        source: "BusinessIntegrationHealth",
        metadata: { health_score: row&.health_score, warning_count: row&.warning_count, warnings: row&.warnings }
      )
    end

    def normalize_health(value)
      case value.to_s.downcase
      when "healthy" then "CONNECTED"
      when "warning" then "WARNING"
      when "broken" then "BROKEN"
      else "NOT_CONFIGURED"
      end
    end

    def label_for(source_key)
      Aicoo::BusinessConnectionStatus::SOURCE_LABELS.fetch(source_key, source_key.upcase)
    end

    def global_detail_url(source_key)
      case source_key
      when "ga4", "gsc"
        admin_google_credentials_path
      when "serp"
        admin_serp_settings_path
      when "codex"
        admin_codex_connection_path
      else
        aicoo_setting_path
      end
    end

    def env_google_credentials_present?
      ENV["GOOGLE_CLIENT_ID"].present? &&
        ENV["GOOGLE_CLIENT_SECRET"].present? &&
        ENV["GOOGLE_REFRESH_TOKEN"].present?
    end

    def credential_usable?(credential)
      credential&.connected? &&
        !credential.reauthentication_required? &&
        !credential.token_expired?
    end
  end
end
