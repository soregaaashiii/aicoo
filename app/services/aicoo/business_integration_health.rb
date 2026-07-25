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

    def initialize(businesses: nil)
      @businesses = businesses
    end

    def call
      businesses = business_scope.to_a
      prepare_aggregate_maps(businesses)
      rows = businesses.map do |business|
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

    def business_scope
      return Business.real_businesses.includes(:business_playbook).order(:name) unless @businesses

      Array(@businesses)
    end

    def build_business_health(business)
      gsc = analytics_health(business, "gsc")
      ga4 = analytics_health(business, "ga4")
      serp = serp_health(business)
      explore = explore_health(business)
      daily_run = daily_run_health
      playbook = playbook_health(business)
      decision_log = decision_log_health(business)
      action_candidate_count = action_candidate_counts.fetch(business.id, 0)
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
      system_status = Aicoo::SystemStatusResolver.call(source_type, business:)
      configured = !system_status.not_configured?
      connected = system_status.connected?
      last_fetched_at = latest_run&.finished_at || latest_run&.started_at || setting&.last_fetched_at
      warning = system_status.connected? ? analytics_warning(source_type, configured:, connected:, latest_success:, latest_run:, last_fetched_at:) : system_status.reason

      SourceHealth.new(
        source: source_type,
        connected:,
        configured:,
        status: system_status.status,
        last_fetched_at:,
        last_success_at: latest_success&.finished_at || latest_success&.started_at,
        last_failed_at: latest_failed&.finished_at || latest_failed&.started_at,
        count: snapshot_count_for(settings),
        warning:
      )
    end

    def analytics_settings_for(business, source_type)
      identifier = analytics_identifier_for(business, source_type)
      analytics_settings.select do |setting|
        next false unless setting.source_type == source_type
        next true if setting.aicoo_analytics_site&.business_id == business.id

        case source_type
        when "gsc"
          identifier.present? && setting.site_url == identifier
        when "ga4"
          identifier.present? && setting.property_id == identifier
        else
          false
        end
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
      analytics_identifier_for(business, source_type).present? ||
        (source_type == "gsc" ? setting&.site_url.present? : setting&.property_id.present?)
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

    def analytics_identifier_for(business, source_type)
      case source_type
      when "gsc"
        business_source_identifier(business, source_type).presence ||
          business.gsc_site_url.presence ||
          AicooAnalyticsSite.where(business:).where.not(gsc_site_url: [ nil, "" ]).recent.first&.gsc_site_url ||
          named_analytics_setting_for(business, source_type)&.site_url
      when "ga4"
        business_source_identifier(business, source_type).presence ||
          AicooAnalyticsSite.where(business:).where.not(ga4_property_id: [ nil, "" ]).recent.first&.ga4_property_id ||
          named_analytics_setting_for(business, source_type)&.property_id
      end
    end

    def named_analytics_setting_for(business, source_type)
      analytics_settings.find do |setting|
        setting.source_type == source_type &&
          setting.enabled? &&
          setting.name.to_s.match?(/\A#{Regexp.escape(business.name)}\b/i)
      end
    end

    def env_google_credentials_present?
      ENV["GOOGLE_CLIENT_ID"].present? &&
        ENV["GOOGLE_CLIENT_SECRET"].present? &&
        ENV["GOOGLE_REFRESH_TOKEN"].present?
    end

    def serp_health(business)
      system_status = Aicoo::SystemStatusResolver.call("serp", business:)
      latest_at = latest_serp_at_by_business_id[business.id]
      count = serp_counts_by_business_id.fetch(business.id, 0)
      warning = if !system_status.connected?
        system_status.reason
      elsif latest_at.blank?
        "SERP分析が未実行です"
      elsif stale?(latest_at)
        "SERPが#{WARNING_STALE_DAYS}日以上更新されていません"
      end
      SourceHealth.new(
        source: "serp",
        connected: system_status.connected?,
        configured: system_status.connected? || system_status.warning?,
        status: system_status.status,
        last_fetched_at: latest_at,
        last_success_at: latest_at,
        last_failed_at: nil,
        count:,
        warning:
      )
    end

    def explore_health(business)
      count = opportunity_counts_by_business_id.fetch(business.id, 0)
      latest_at = [
        latest_opportunity_at_by_business_id[business.id],
        latest_observation_at_by_business_id[business.id]
      ].compact.max
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
      return @daily_run_health if defined?(@daily_run_health)

      system_status = Aicoo::SystemStatusResolver.call("daily_run")
      latest = AicooDailyRun.recent.first
      warning = if !system_status.connected?
        system_status.reason
      elsif latest.blank?
        "Daily Run未実行"
      elsif latest.status.in?(%w[failed stuck])
        "Daily Runが#{latest.status}です"
      elsif latest.status == "partial_failed"
        "Daily Runがpartial_failedです"
      elsif stale?(latest.finished_at || latest.started_at)
        "Daily Run成功が#{WARNING_STALE_DAYS}日以上ありません"
      end
      @daily_run_health = SourceHealth.new(
        source: "daily_run",
        connected: system_status.connected?,
        configured: true,
        status: system_status.status,
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
      rows = decision_logs_by_business_id.fetch(business.id, [])
      today = rows.count { |decided_at| decided_at.in?(Time.current.all_day) }
      last_7_days = rows.count { |decided_at| decided_at >= 7.days.ago }
      last_30_days = rows.count { |decided_at| decided_at >= 30.days.ago }
      latest_at = latest_decision_at_by_business_id[business.id]
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

    def prepare_aggregate_maps(businesses)
      @business_ids = businesses.filter_map(&:id)
      @action_candidate_counts = ActionCandidate.where(business_id: @business_ids, created_at: 30.days.ago..)
        .group(:business_id)
        .count
      @serp_counts_by_business_id = SerpAnalysis.where(business_id: @business_ids).group(:business_id).count
      @latest_serp_at_by_business_id = SerpAnalysis.where(business_id: @business_ids).group(:business_id).maximum(:analyzed_at)
      opportunity_scope = OpportunityDiscoveryItem.where(business_id: @business_ids)
      @opportunity_counts_by_business_id = opportunity_scope.group(:business_id).count
      @latest_opportunity_at_by_business_id = opportunity_scope.group(:business_id).maximum(:created_at)
      @latest_observation_at_by_business_id = ExploreObservation
        .joins(:opportunity_discovery_item)
        .where(opportunity_discovery_items: { business_id: @business_ids })
        .group("opportunity_discovery_items.business_id")
        .maximum(:observed_at)
      decision_scope = OwnerDecisionLog.where(business_id: @business_ids)
      @latest_decision_at_by_business_id = decision_scope.group(:business_id).maximum(:decided_at)
      @decision_logs_by_business_id = decision_scope
        .where(decided_at: 30.days.ago..)
        .pluck(:business_id, :decided_at)
        .group_by(&:first)
        .transform_values { |rows| rows.map(&:last) }
    end

    attr_reader :action_candidate_counts,
                :serp_counts_by_business_id,
                :latest_serp_at_by_business_id,
                :opportunity_counts_by_business_id,
                :latest_opportunity_at_by_business_id,
                :latest_observation_at_by_business_id,
                :decision_logs_by_business_id,
                :latest_decision_at_by_business_id

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
