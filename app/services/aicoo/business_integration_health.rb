module Aicoo
  class BusinessIntegrationHealth
    SourceHealth = Data.define(
      :source,
      :connected,
      :configured,
      :status,
      :last_fetched_at,
      :last_success_at,
      :last_failed_at,
      :count,
      :warning
    )
    BusinessHealth = Data.define(
      :business,
      :health_score,
      :warning_count,
      :warnings,
      :last_sync_at,
      :gsc,
      :ga4,
      :serp,
      :explore,
      :daily_run,
      :playbook,
      :decision_log,
      :action_candidate_count
    )
    Result = Data.define(
      :generated_at,
      :business_healths,
      :average_health_score,
      :critical_businesses,
      :warning_businesses,
      :healthy_businesses
    )

    WARNING_STALE_DAYS = 3
    LOW_HEALTH_THRESHOLD = 60
    ATTENTION_HEALTH_THRESHOLD = 80

    def call
      rows = Business.includes(:business_playbook).order(:name).map do |business|
        build_business_health(business)
      end
      Result.new(
        generated_at: Time.current,
        business_healths: rows,
        average_health_score: average(rows.map(&:health_score)),
        critical_businesses: rows.select { |row| row.health_score < LOW_HEALTH_THRESHOLD },
        warning_businesses: rows.select { |row| row.health_score >= LOW_HEALTH_THRESHOLD && row.health_score < ATTENTION_HEALTH_THRESHOLD },
        healthy_businesses: rows.select { |row| row.health_score >= ATTENTION_HEALTH_THRESHOLD }
      )
    end

    private

    def build_business_health(business)
      gsc = analytics_health(business, "gsc")
      ga4 = analytics_health(business, "ga4")
      serp = serp_health(business)
      explore = explore_health(business)
      daily_run = daily_run_health
      playbook = playbook_health(business)
      decision_log = decision_log_health(business)
      action_candidate_count = business.action_candidates.where(created_at: 30.days.ago..).count
      warnings = [
        gsc.warning,
        ga4.warning,
        serp.warning,
        explore.warning,
        daily_run.warning,
        playbook.warning,
        decision_log.warning,
        ("ActionCandidateが30日以内に生成されていません" if action_candidate_count.zero?)
      ].compact
      score = score_for(
        gsc:,
        ga4:,
        serp:,
        explore:,
        daily_run:,
        playbook:,
        decision_log:,
        action_candidate_count:
      )

      BusinessHealth.new(
        business:,
        health_score: score,
        warning_count: warnings.size,
        warnings:,
        last_sync_at: [ gsc.last_fetched_at, ga4.last_fetched_at, serp.last_fetched_at, explore.last_fetched_at ].compact.max,
        gsc:,
        ga4:,
        serp:,
        explore:,
        daily_run:,
        playbook:,
        decision_log:,
        action_candidate_count:
      )
    end

    def analytics_health(business, source_type)
      settings = analytics_settings_for(business, source_type)
      latest_runs_by_setting = settings.index_with { |record| latest_fetch_run_for(record) }
      setting = settings.max_by { |record| latest_runs_by_setting[record]&.started_at || record.updated_at }
      latest_run = setting ? latest_runs_by_setting[setting] : nil
      latest_success = latest_fetch_run(settings, "success")
      latest_failed = latest_fetch_run(settings, "failed")
      configured = configured_analytics?(business, source_type, setting)
      connected = configured && analytics_connection_available?(business, source_type, setting)
      last_fetched_at = latest_run&.finished_at || latest_run&.started_at || setting&.last_fetched_at
      warning = analytics_warning(source_type, configured:, connected:, latest_success:, latest_run:, last_fetched_at:)

      SourceHealth.new(
        source: source_type,
        connected:,
        configured:,
        status: latest_run&.status || (configured ? "configured" : "missing"),
        last_fetched_at:,
        last_success_at: latest_success&.finished_at || latest_success&.started_at,
        last_failed_at: latest_failed&.finished_at || latest_failed&.started_at,
        count: snapshot_count_for(settings),
        warning:
      )
    end

    def analytics_settings_for(business, source_type)
      analytics_settings.select do |setting|
        next false unless setting.source_type == source_type
        next true if setting.aicoo_analytics_site&.business_id == business.id

        source_type == "gsc" && business.gsc_site_url.present? && setting.site_url == business.gsc_site_url
      end
    end

    def latest_fetch_run(settings, status)
      AnalyticsFetchRun
        .where(analytics_source_setting_id: settings.map(&:id), status:)
        .recent
        .first
    end

    def latest_fetch_run_for(setting)
      AnalyticsFetchRun.where(analytics_source_setting_id: setting.id).recent.first
    end

    def snapshot_count_for(settings)
      return 0 if settings.empty?

      AnalyticsFetchRun.where(analytics_source_setting_id: settings.map(&:id)).sum(:snapshot_count)
    end

    def analytics_settings
      @analytics_settings ||= AnalyticsSourceSetting.includes(:aicoo_analytics_site).to_a
    end

    def configured_analytics?(business, source_type, setting)
      if source_type == "gsc"
        business.gsc_site_url.present? ||
          setting&.site_url.present? ||
          business_source_identifier(business, source_type).present?
      else
        setting&.property_id.present? ||
          AicooAnalyticsSite.where(business:).where.not(ga4_property_id: [ nil, "" ]).exists? ||
          business_source_identifier(business, source_type).present?
      end
    end

    def analytics_warning(source_type, configured:, connected:, latest_success:, latest_run:, last_fetched_at:)
      label = source_type.upcase
      return "#{label}未接続" unless configured
      return "#{label}未接続" unless connected
      return "#{label}最終取得が失敗しています" if latest_run&.status == "failed"
      return "#{label}取得成功がまだありません" unless latest_success
      return "#{label}が#{WARNING_STALE_DAYS}日以上更新されていません" if stale?(last_fetched_at)

      nil
    end

    def google_auth_available?(setting)
      return false unless setting
      return setting.individual_credentials_present? if setting.individual_authentication?

      setting.effective_google_credential.present? ||
        (setting.google_credential.blank? && AicooGoogleCredential.default&.connected?) ||
        env_google_credentials_present?
    end

    def analytics_connection_available?(business, source_type, setting)
      return true if google_auth_available?(setting)
      return false unless uses_global_business_source?(business, source_type)

      AicooGoogleCredential.default&.connected? || env_google_credentials_present?
    end

    def uses_global_business_source?(business, source_type)
      setting = BusinessDataSourceSetting.find_by(business:, source_key: source_type)
      return false unless setting&.enabled?

      ActiveModel::Type::Boolean.new.cast(setting.metadata.to_h.dig("source_binding", "use_global") || true)
    end

    def business_source_identifier(business, source_type)
      setting = BusinessDataSourceSetting.find_by(business:, source_key: source_type)
      return nil unless setting&.enabled?

      case source_type
      when "gsc"
        setting.connection_field_value("site_url").presence ||
          setting.property_identifier.presence ||
          business.gsc_site_url.presence
      when "ga4"
        setting.connection_field_value("property_id").presence ||
          setting.property_identifier.presence
      end
    end

    def env_google_credentials_present?
      ENV["GOOGLE_CLIENT_ID"].present? &&
        ENV["GOOGLE_CLIENT_SECRET"].present? &&
        ENV["GOOGLE_REFRESH_TOKEN"].present?
    end

    def serp_health(business)
      latest = business.serp_analyses.order(analyzed_at: :desc).first
      count = business.serp_analyses.count
      warning = if latest.blank?
        "SERP分析が未実行です"
      elsif stale?(latest.analyzed_at)
        "SERPが#{WARNING_STALE_DAYS}日以上更新されていません"
      end
      SourceHealth.new(
        source: "serp",
        connected: latest.present?,
        configured: true,
        status: latest ? "success" : "missing",
        last_fetched_at: latest&.analyzed_at,
        last_success_at: latest&.analyzed_at,
        last_failed_at: nil,
        count:,
        warning:
      )
    end

    def explore_health(business)
      opportunities = business.opportunity_discovery_items
      observations = ExploreObservation.where(opportunity_discovery_item_id: opportunities.select(:id))
      count = opportunities.count
      latest_at = [ opportunities.maximum(:created_at), observations.maximum(:observed_at) ].compact.max
      warning = if count.zero?
        "Opportunityが生成されていません"
      elsif stale?(latest_at)
        "Explore/Opportunityが#{WARNING_STALE_DAYS}日以上更新されていません"
      end
      SourceHealth.new(
        source: "explore",
        connected: count.positive?,
        configured: true,
        status: count.positive? ? "success" : "missing",
        last_fetched_at: latest_at,
        last_success_at: latest_at,
        last_failed_at: nil,
        count:,
        warning:
      )
    end

    def daily_run_health
      latest = AicooDailyRun.recent.first
      warning = if latest.blank?
        "Daily Run未実行"
      elsif latest.status.in?(%w[failed stuck])
        "Daily Runが#{latest.status}です"
      elsif latest.status == "partial_failed"
        "Daily Runがpartial_failedです"
      elsif stale?(latest.finished_at || latest.started_at)
        "Daily Run成功が#{WARNING_STALE_DAYS}日以上ありません"
      end
      SourceHealth.new(
        source: "daily_run",
        connected: latest&.succeeded? || false,
        configured: true,
        status: latest&.status || "missing",
        last_fetched_at: latest&.finished_at || latest&.started_at,
        last_success_at: AicooDailyRun.successful.recent.first&.finished_at,
        last_failed_at: AicooDailyRun.where(status: %w[failed stuck partial_failed]).recent.first&.finished_at,
        count: AicooDailyRun.count,
        warning:
      )
    end

    def playbook_health(business)
      playbook = business.business_playbook
      warning = if playbook.blank? || !playbook.learned?
        "Playbook未学習"
      elsif playbook.confidence_score.to_d < 40
        "Playbook confidenceが低いです"
      end
      SourceHealth.new(
        source: "playbook",
        connected: playbook&.learned? || false,
        configured: true,
        status: playbook&.learned? ? "learned" : "insufficient",
        last_fetched_at: playbook&.last_calculated_at,
        last_success_at: playbook&.last_calculated_at,
        last_failed_at: nil,
        count: playbook&.sample_count.to_i,
        warning:
      )
    end

    def decision_log_health(business)
      today = OwnerDecisionLog.where(business:, decided_at: Time.current.all_day).count
      last_7_days = OwnerDecisionLog.where(business:, decided_at: 7.days.ago..).count
      last_30_days = OwnerDecisionLog.where(business:, decided_at: 30.days.ago..).count
      latest_at = OwnerDecisionLog.where(business:).maximum(:decided_at)
      warning = "Decision Log不足" if last_30_days < 3
      SourceHealth.new(
        source: "decision_log",
        connected: last_30_days.positive?,
        configured: true,
        status: last_30_days.positive? ? "active" : "insufficient",
        last_fetched_at: latest_at,
        last_success_at: latest_at,
        last_failed_at: nil,
        count: last_30_days,
        warning:,
      ).then do |health|
        health.with(count: { "today" => today, "7d" => last_7_days, "30d" => last_30_days })
      end
    end

    def score_for(gsc:, ga4:, serp:, explore:, daily_run:, playbook:, decision_log:, action_candidate_count:)
      score = 0.to_d
      score += component_score(gsc, weight: 18)
      score += component_score(ga4, weight: 18)
      score += component_score(serp, weight: 12)
      score += component_score(explore, weight: 12)
      score += component_score(daily_run, weight: 16)
      score += component_score(playbook, weight: 12)
      score += component_score(decision_log, weight: 8)
      score += action_candidate_count.positive? ? 4 : 0
      [ score, 100.to_d ].min.round(1)
    end

    def component_score(health, weight:)
      return weight.to_d if health.connected && health.warning.blank?
      return weight.to_d * 0.55 if health.configured && health.warning.present?
      return weight.to_d * 0.2 if health.configured

      0.to_d
    end

    def stale?(time)
      return true if time.blank?

      time < WARNING_STALE_DAYS.days.ago
    end

    def average(values)
      values = values.compact.map(&:to_d)
      return 0.to_d if values.empty?

      (values.sum / values.size).round(1)
    end
  end
end
