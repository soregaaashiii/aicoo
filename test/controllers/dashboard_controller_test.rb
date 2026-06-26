require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows lightweight system mode monitor from snapshot presenter" do
    Aicoo::SystemModeSnapshotBuilder.new.call

    get dashboard_url

    assert_response :success
    assert_includes response.body, "AICOO SYSTEM MODE"
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
    assert_includes response.body, "Cost Summary"
    assert_includes response.body, "Data Source Monitor"
    assert_includes response.body, "Analysis Monitor"
    assert_includes response.body, "月間APIコスト"
    assert_not_includes response.body, "AICOO TODAY"
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
