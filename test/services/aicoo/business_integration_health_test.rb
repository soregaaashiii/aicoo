require "test_helper"

module Aicoo
  class BusinessIntegrationHealthTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.update!(gsc_site_url: "sc-domain:suelog.test")
      AnalyticsFetchRun.delete_all
      AnalyticsSourceSetting.delete_all
      AicooAnalyticsSite.delete_all
      AicooDailyRun.delete_all
      BusinessPlaybook.delete_all
      OwnerDecisionLog.delete_all
      ExploreObservation.delete_all
      ExploreDataSource.delete_all
      OpportunityDiscoveryItem.delete_all
      SerpAnalysis.delete_all
      DataSourceCostProfile.ensure_defaults!
    end

    test "returns low health with warnings when integrations are missing" do
      result = BusinessIntegrationHealth.new.call
      health = result.business_healths.find { |row| row.business == @business }

      assert health
      assert_operator health.health_score, :<, BusinessIntegrationHealth::LOW_HEALTH_THRESHOLD
      assert_includes health.warnings, "sc-domain:suelog.test"
      assert_includes health.warnings, "Google全体設定がありません"
      assert_includes health.warnings, "Daily Run履歴がありません。"
      assert_includes result.critical_businesses, health
    end

    test "excludes system businesses from health result" do
      system_business = Business.create!(
        name: "AICOO Analytics Import",
        description: "system import holder",
        status: "launched"
      )

      result = BusinessIntegrationHealth.new.call

      assert_not_includes result.business_healths.map(&:business), system_business
      assert_not_includes result.critical_businesses.map(&:business), system_business
    end

    test "aggregates configured integrations and lowers warnings for healthy data" do
      create_successful_analytics_settings
      @business.serp_analyses.create!(
        keyword: "シーシャ 大阪",
        device: "desktop",
        result_count: 10,
        analyzed_at: Time.current
      )
      DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "serp-key")
      @business.serp_queries.create!(query: "シーシャ 大阪", enabled: true, status: "active")
      opportunity = OpportunityDiscoveryItem.create!(
        business: @business,
        title: "Explore opportunity",
        source_type: "google_trends",
        status: "pending",
        opportunity_score: 90
      )
      source = ExploreDataSource.create!(name: "Trends", source_type: "google_trends", status: "active")
      ExploreObservation.create!(
        explore_data_source: source,
        opportunity_discovery_item: opportunity,
        title: "大阪 シーシャ需要",
        observation_type: "trend",
        score: 85,
        observed_at: Time.current
      )
      AicooDailyRun.create!(
        target_date: Date.current,
        source: "manual",
        status: "success",
        started_at: Time.current,
        finished_at: Time.current
      )
      @business.create_business_playbook!(sample_count: 5, confidence_score: 55, last_calculated_at: Time.current)
      OwnerDecisionLog.create!(
        subject_type: "ActionCandidate",
        subject_id: 1,
        business: @business,
        decision_type: "approve",
        decision_source: "owner_focus",
        title: "Approved",
        decided_at: Time.current
      )
      @business.action_candidates.create!(
        title: "CTR改善",
        status: "idea",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 1,
        expected_hours: 1
      )

      health = BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }

      assert_operator health.health_score, :>=, BusinessIntegrationHealth::ATTENTION_HEALTH_THRESHOLD
      assert_nil health.gsc.warning
      assert_nil health.ga4.warning
      assert_nil health.serp.warning
      assert_nil health.explore.warning
      assert_nil health.daily_run.warning
      assert_equal({ "today" => 1, "7d" => 1, "30d" => 1 }, health.decision_log.count)
    end

    test "warns when analytics data is stale" do
      site = AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/123"
      )
      credential = create_google_credential
      site.gsc_setting.update!(google_credential: credential)
      site.ga4_setting.update!(google_credential: credential)
      setting = site.gsc_setting
      setting.analytics_fetch_runs.create!(
        status: "success",
        source_type: "gsc",
        snapshot_count: 10,
        started_at: 5.days.ago,
        finished_at: 5.days.ago
      )

      health = BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }

      assert_equal "GSCが3日以上更新されていません", health.gsc.warning
    end

    test "treats shared google credential refresh token as connected before first fetch" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
      site = AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/123",
        authentication_mode: "shared"
      )
      site.gsc_setting.update!(google_credential: credential)
      site.ga4_setting.update!(google_credential: credential)

      health = BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }

      assert health.gsc.connected
      assert health.ga4.connected
      assert_equal "GSC取得成功がまだありません", health.gsc.warning
      assert_equal "GA4取得成功がまだありません", health.ga4.warning
      refute_includes health.warnings, "GSC未接続"
      refute_includes health.warnings, "GA4未接続"
    end

    test "matches ga4 setting by analytics site property id" do
      credential = create_google_credential
      site = AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/999",
        authentication_mode: "shared"
      )
      ga4_setting = site.ga4_setting
      ga4_setting.update!(google_credential: credential)
      ga4_setting.analytics_fetch_runs.create!(
        status: "success",
        source_type: "ga4",
        snapshot_count: 7,
        started_at: Time.current,
        finished_at: Time.current
      )

      health = BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }

      assert health.ga4.configured
      assert health.ga4.connected
      assert_nil health.ga4.warning
      assert_equal 7, health.ga4.count
    end

    test "matches ga4 setting by business named setting without analytics site" do
      credential = create_google_credential
      ga4_setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "#{@business.name} GA4",
        property_id: "536889590",
        enabled: true,
        authentication_mode: "shared",
        google_credential: credential
      )
      ga4_setting.analytics_fetch_runs.create!(
        status: "failed",
        source_type: "ga4",
        snapshot_count: 0,
        error_message: "invalid_grant",
        started_at: Time.current,
        finished_at: Time.current
      )

      health = BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }

      assert health.ga4.configured
      refute health.ga4.connected
      assert_equal "Google再認証が必要です", health.ga4.warning
      assert_equal 0, health.ga4.count
    end

    test "does not treat shared google credential without refresh token as connected" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        connected_at: Time.current
      )
      site = AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/123",
        authentication_mode: "shared"
      )
      site.gsc_setting.update!(google_credential: credential)
      site.ga4_setting.update!(google_credential: credential)

      health = BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }

      refute health.gsc.connected
      refute health.ga4.connected
      assert_includes health.warnings, "Google再認証が必要です"
    end

    private

    def create_successful_analytics_settings
      site = AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/123"
      )
      credential = create_google_credential
      site.gsc_setting.update!(google_credential: credential)
      site.ga4_setting.update!(google_credential: credential)
      [ site.gsc_setting, site.ga4_setting ].each do |setting|
        setting.analytics_fetch_runs.create!(
          status: "success",
          source_type: setting.source_type,
          snapshot_count: 25,
          started_at: Time.current,
          finished_at: Time.current
        )
      end
    end

    def create_google_credential
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
    end
  end
end
