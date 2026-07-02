require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows lightweight system mode monitor from snapshot presenter" do
    Aicoo::SystemModeSnapshotBuilder.new.call

    get dashboard_url

    assert_response :success
    assert_includes response.body, "AICOO SYSTEM MODE"
    assert_includes response.body, "Daily Runs"
    assert_includes response.body, "Cron Health"
    assert_includes response.body, "Google"
    assert_includes response.body, "SERP"
    assert_includes response.body, "Pipeline E2E"
    assert_includes response.body, "Activity Learning"
    assert_includes response.body, "DataHub"
    assert_includes response.body, "Calibration"
    assert_includes response.body, "Judge"
    assert_includes response.body, "Resource Budget"
    assert_includes response.body, "Source App"
    assert_includes response.body, "Execution Profiles"
    assert_includes response.body, "Codex Rules"
    assert_not_includes response.body, "今日どのBusinessを改善するか"
    assert_includes response.body, "System Mode Monitor"
    assert_includes response.body, "System Health Score"
    assert_includes response.body, "Snapshot"
    assert_includes response.body, "最終Snapshot"
    assert_includes response.body, "Refresh"
    assert_includes response.body, "Visual Analytics"
    assert_includes response.body, "Prediction Accuracy"
    assert_includes response.body, "Health Trend"
    assert_includes response.body, "Pipeline Monitor"
    assert_includes response.body, "Integrations"
    assert_includes response.body, "Jobs"
    assert_includes response.body, "Queues"
    assert_includes response.body, "Learning"
    assert_includes response.body, "Playbook"
    assert_includes response.body, "Executor"
    assert_includes response.body, "Settings"
    assert_includes response.body, "Resource Control"
    assert_includes response.body, "今日見るBusiness"
    assert_includes response.body, "CEO向け改善サマリー"
    assert_includes response.body, "今日の改善 TOP5"
    assert_includes response.body, "今日改善すべきBusiness"
    assert_includes response.body, "期待利益ランキング"
    assert_includes response.body, "Cost Summary"
    assert_includes response.body, "Data Source Monitor"
    assert_includes response.body, "Analysis Monitor"
    assert_includes response.body, "MVP Promotion"
    assert_includes response.body, "Production昇格候補"
    assert_includes response.body, "Scaling中Business"
    assert_includes response.body, "月間APIコスト"
    assert_not_includes response.body, "AICOO TODAY"
  end

  test "dashboard shows resource control counts" do
    businesses(:suelog).update!(resource_status: "watch")
    businesses(:cards).update!(resource_status: "paused")

    get dashboard_url

    assert_response :success
    assert_includes response.body, "Watch"
    assert_includes response.body, "Paused"
    assert_includes response.body, "Archived"
  end

  test "dashboard shows production promotion candidates" do
    business = businesses(:suelog)
    business.update!(lifecycle_stage: "mvp", created_by_aicoo: true)
    business.business_services.create!(
      name: "Dashboard Production MVP",
      status: "live",
      url: "https://dashboard-production.example.com",
      metadata: { registrations: 8, active_users: 5, paid_users: 1, retention_rate: "0.5" }
    )
    business.revenue_events.create!(event_type: "revenue", amount: 15_000, occurred_on: Date.current)

    get dashboard_url

    assert_response :success
    assert_includes response.body, "Production候補"
    assert_includes response.body, business.name
  end

  test "dashboard shows scaling candidates" do
    business = businesses(:suelog)
    business.update!(lifecycle_stage: "production", created_by_aicoo: true, status: "launched", launched: true)
    business.business_services.create!(
      name: "Dashboard Scaling Service",
      status: "production",
      metadata: {
        paid_users: 6,
        active_users: 15,
        registrations: 20,
        retention_rate: "0.65",
        cac_hypothesis_yen: 7_000,
        ltv_hypothesis_yen: 70_000,
        primary_channel: "SEO"
      }
    )
    business.revenue_events.create!(event_type: "revenue", amount: 120_000, occurred_on: Date.current)
    business.revenue_events.create!(event_type: "expense", amount: 10_000, occurred_on: Date.current)
    business.business_metric_dailies.create!(recorded_on: Date.current, sessions: 100, conversions: 6, impressions: 1_000)

    get dashboard_url

    assert_response :success
    assert_includes response.body, "Scaling候補"
    assert_includes response.body, business.name
  end

  test "dashboard shows mvp promotion candidates" do
    business = businesses(:suelog)
    business.update!(lifecycle_stage: "lp_validation", created_by_aicoo: true)
    experiment = AicooLabExperiment.create!(
      title: "Dashboard MVP LP",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "running",
      approval_status: "approved"
    )
    landing_page = experiment.create_aicoo_lab_landing_page!(
      business:,
      headline: "Dashboard MVP LP",
      subheadline: "MVP昇格候補",
      body: "反応が良いLP",
      cta_text: "登録する",
      status: "published",
      public_status: "published",
      published_slug: "dashboard-mvp-lp",
      published_at: Time.current
    )
    3.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click", occurred_at: Time.current) }

    get dashboard_url

    assert_response :success
    assert_includes response.body, "MVP昇格候補"
    assert_includes response.body, business.name
  end

  test "dashboard falls back when snapshot is missing" do
    SystemModeSnapshot.delete_all

    get dashboard_url

    assert_response :success
    assert_includes response.body, "Snapshot未作成"
    assert_includes response.body, "System Mode Monitor"
  end

  test "manual refresh regenerates system mode snapshot" do
    assert_difference("SystemModeSnapshot.count", 1) do
      post refresh_system_mode_snapshot_dashboard_url
    end

    assert_redirected_to dashboard_url
    assert_match(/System Mode Snapshotを更新しました/, flash[:notice])
  end

  test "generates action candidates from metrics from dashboard" do
    post generate_action_candidates_from_metrics_dashboard_url

    assert_redirected_to dashboard_url
    assert_match(/代理指標から行動候補を/, flash[:notice])
  end

  test "generates analysis candidates from dashboard" do
    AnalysisCandidate.delete_all

    before_count = AnalysisCandidate.count
    post generate_analysis_candidates_dashboard_url

    assert_redirected_to dashboard_url
    assert_operator AnalysisCandidate.count, :>, before_count
    assert_match(/Analysis Candidateを/, flash[:notice])
  end

  test "generates action candidates from correction readiness from dashboard" do
    assert_difference("ActionCandidate.count", Business.count) do
      post generate_correction_readiness_actions_dashboard_url
    end

    assert_redirected_to dashboard_url
    assert_match(/補正できない理由から行動候補を/, flash[:notice])
  end

  test "builds auto revision approval queue from dashboard" do
    ActionCandidate.update_all(status: "done")
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Dashboard auto revision queue candidate",
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 20_000,
      success_probability: 1,
      expected_hours: 1,
      execution_prompt: "SEOタイトルを改善してください。"
    )

    assert_difference("AutoRevisionTask.count", 1) do
      post build_auto_revision_queue_dashboard_url
    end

    assert_redirected_to dashboard_url
    assert_match(/Auto Revision承認待ちタスクを1件作成しました/, flash[:notice])
  end

  test "backfills business metrics from dashboard date range" do
    assert_difference("BusinessMetricDaily.count", Business.count * 2) do
      post backfill_business_metrics_dashboard_url, params: {
        start_date: "2026-06-01",
        end_date: "2026-06-02"
      }
    end

    assert_redirected_to dashboard_url
    assert_equal "2026-06-01〜2026-06-02の代理指標を#{Business.count * 2}件更新しました。", flash[:notice]
  end

  test "dashboard backfill shows clear alert for invalid dates" do
    post backfill_business_metrics_dashboard_url, params: {
      start_date: "bad-date",
      end_date: "2026-06-02"
    }

    assert_redirected_to dashboard_url
    assert_match(/代理指標の期間バックフィルに失敗しました/, flash[:alert])
  end

  test "adjusts proxy score weights from dashboard actions" do
    assert_difference("ProxyScoreWeightAdjustmentLog.count", 1) do
      post adjust_global_proxy_score_weights_dashboard_url
    end
    assert_redirected_to dashboard_url

    assert_difference("ProxyScoreWeightAdjustmentLog.count", Business.count) do
      post adjust_all_business_proxy_score_weights_dashboard_url
    end
    assert_redirected_to dashboard_url
  end
end
