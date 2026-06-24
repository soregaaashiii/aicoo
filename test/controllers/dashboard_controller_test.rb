require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows AICOO Lab metric summary" do
    experiment = AicooLabExperiment.create!(title: "Dashboard metric test", experiment_type: "lp", acquisition_channel: "sns")
    AutoRevisionTask.create!(
      action_candidate: action_candidates(:nagazakicho_article),
      business: businesses(:suelog),
      title: "Dashboard completed auto revision",
      execution_prompt: "文言を改善する",
      status: "partial_succeeded",
      risk_level: "low",
      finished_at: Time.current
    )
    experiment.update!(current_pv: 1_000, sample_pv_threshold: 1_000)
    landing_page = experiment.create_aicoo_lab_landing_page!(
      headline: "Dashboard headline",
      subheadline: "Dashboard subheadline",
      body: "Dashboard body",
      cta_text: "事前登録する"
    )
    landing_page.aicoo_lab_landing_page_events.create!(event_type: "view")
    landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click")
    landing_page.aicoo_lab_signups.create!(email: "dashboard@example.com")

    get dashboard_url

    assert_response :success
    assert_includes response.body, "AICOO SYSTEM MODE"
    assert_includes response.body, "SYSTEM MODE"
    assert_includes response.body, "CEO MODEへ"
    assert_includes response.body, "CEOダッシュボードへ戻る"
    assert_includes response.body, "AICOO TODAY"
    assert_includes response.body, "今日の確認タスク"
    assert_includes response.body, "今日の確認ダイジェスト"
    assert_includes response.body, "確認タスク一覧へ"
    assert_includes response.body, "Auto Revision Tasks"
    assert_includes response.body, "Auto Revision Approval Queue"
    assert_includes response.body, "承認待ちタスクを自動生成"
    assert_includes response.body, "自動生成設定"
    assert_includes response.body, "最終自動実行"
    assert_includes response.body, "前回生成"
    assert_includes response.body, "Codex Executor"
    assert_includes response.body, "Codex Queueを見る"
    assert_includes response.body, "ready_for_codex"
    assert_includes response.body, "sent_to_codex"
    assert_includes response.body, "7日以上放置"
    assert_includes response.body, "最終確認が古い"
    assert_includes response.body, "target valid"
    assert_includes response.body, "target warning"
    assert_includes response.body, "target invalid"
    assert_includes response.body, "export済み"
    assert_includes response.body, "未export"
    assert_includes response.body, "export不可"
    assert_includes response.body, "quality passed"
    assert_includes response.body, "quality review_required"
    assert_includes response.body, "gate pending"
    assert_includes response.body, "gate approved"
    assert_includes response.body, "Quality Gateを見る"
    assert_includes response.body, "Repository Target Coverage"
    assert_includes response.body, "Coverage"
    assert_includes response.body, "Execution Profileを設定"
    assert_includes response.body, "未設定"
    assert_includes response.body, "不完全"
    assert_includes response.body, "無効化"
    assert_includes response.body, "推定合計スコア"
    assert_includes response.body, "高リスク候補あり"
    assert_includes response.body, "partial_succeeded"
    assert_includes response.body, "最近完了"
    assert_includes response.body, "AICOO完成段階"
    assert_includes response.body, "Lv1 事業管理"
    assert_includes response.body, "Lv2 データ分析"
    assert_includes response.body, "Lv3 行動提案"
    assert_includes response.body, "Lv4 結果評価"
    assert_includes response.body, "Lv5 評価式改善"
    assert_includes response.body, "Lv6 自動実行"
    assert_includes response.body, "Lv7 自動ピボット"
    assert_includes response.body, "不足:"
    assert_includes response.body, "分析設定へ"
    assert_includes response.body, "候補を見る"
    assert_includes response.body, "実行結果へ"
    assert_includes response.body, "部門別精度へ"
    assert_includes response.body, "実行指示へ"
    assert_includes response.body, "将来実装"
    assert_includes response.body, "Insight Engine"
    assert_includes response.body, "Insight件数"
    assert_includes response.body, "今日生成した改善案"
    assert_includes response.body, "最重要改善案"
    assert_includes response.body, "最終Insight生成日時"
    assert_includes response.body, "Insight生成失敗件数"
    assert_includes response.body, "改善案を見る"
    assert_includes response.body, "総合ランキング TOP10"
    assert_includes response.body, "Revenue 1位"
    assert_includes response.body, "Lab 1位"
    assert_includes response.body, "新規事業 1位"
    assert_includes response.body, "期待利益"
    assert_includes response.body, "部門別ランキングを見る"
    assert_includes response.body, "部門別精度サマリー"
    assert_includes response.body, "予測との差"
    assert_includes response.body, "AICOO Learning Loop"
    assert_includes response.body, "提案 → 実行 → 差分 → 結果 → 補正 → 次回提案"
    assert_includes response.body, "実行ログ登録率"
    assert_includes response.body, "Learning Loop Action Center"
    assert_includes response.body, "実行ログ待ち"
    assert_includes response.body, "結果登録待ち"
    assert_includes response.body, "売上登録待ち"
    assert_includes response.body, "Action Centerへ"
    assert_includes response.body, "最近の学習イベント"
    assert_includes response.body, "Execution Feasibility Insight"
    assert_includes response.body, "ActionExecutionLog"
    assert_includes response.body, "平均完了率"
    assert_includes response.body, "Execution Correction Overview"
    assert_includes response.body, "補正率が高い action_type"
    assert_includes response.body, "最近補正された候補"
    assert_includes response.body, "評価関数精度"
    assert_includes response.body, "補正係数を見る"
    assert_includes response.body, "warning中"
    assert_includes response.body, "danger中"
    assert_includes response.body, "ランキング変動候補"
    assert_includes response.body, "承認待ち補正"
    assert_includes response.body, "danger承認待ち"
    assert_includes response.body, "aicoo-card-grid"
    assert_includes response.body, "table-wrap"
    assert_includes response.body, "今日やるべきこと TOP10"
    assert_includes response.body, "Judge補正後スコア"
    assert_includes response.body, "Judge補正の順位変動"
    assert_includes response.body, "今日の順位上昇TOP5"
    assert_includes response.body, "今日の順位低下TOP5"
    assert_includes response.body, "補正できない理由"
    assert_includes response.body, "Judgeデータ不足"
    assert_includes response.body, "データ整備タスク"
    assert_includes response.body, "Data Preparation Queue"
    assert_includes response.body, "自動投入OFF"
    assert_includes response.body, "AICOO設定で切り替える"
    assert_includes response.body, "approval_pending"
    assert_includes response.body, "今日追加"
    assert_includes response.body, "Top Generation Source"
    assert_includes response.body, "Top Business"
    assert_includes response.body, "総PV"
    assert_includes response.body, "総CTAクリック"
    assert_includes response.body, "総Signup"
    assert_includes response.body, "1000PV到達実験数"
  end

  test "shows data preparation auto queue on state" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: true)

    get dashboard_url

    assert_response :success
    assert_includes response.body, "自動投入ON"
  end

  test "shows public lp deployment status and local url warning" do
    host! "127.0.0.1"

    get dashboard_url

    assert_response :success
    assert_includes response.body, "LP外部公開URL"
    assert_includes response.body, "外部共有不可"
    assert_includes response.body, "/aicoo_lab/lp/:slug"
  end

  test "shows business revenue profit summary and supports profit sort" do
    suelog = businesses(:suelog)
    cards = businesses(:cards)
    suelog.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 2_000)
    suelog.revenue_events.create!(occurred_on: Date.current, event_type: "expense", amount: 500)
    cards.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 5_000)
    suelog.business_metric_dailies.create!(recorded_on: Date.current, impressions: 1_000)
    cards.business_metric_dailies.create!(recorded_on: Date.current, affiliate_clicks: 10)

    get dashboard_url(business_sort: "current_month_profit")

    assert_response :success
    assert_includes response.body, "今月利益"
    assert_includes response.body, "累計利益"
    assert_includes response.body, "今月 proxy_score"
    assert_includes response.body, "累計 proxy_score"
    assert_includes response.body, "今月 impressions"
    assert_includes response.body, "今月 clicks"
    assert_includes response.body, "今月 sessions"
    assert_includes response.body, "今月 pageviews"
    assert_includes response.body, "今月 phone_clicks"
    assert_includes response.body, "今月 map_clicks"
    assert_includes response.body, "今月 affiliate_clicks"
    assert_includes response.body, "直近7日 proxy_score"
    assert_includes response.body, "直近30日 proxy_score"
    assert_includes response.body, "評価軸"
    assert_includes response.body, "今日の代理指標を更新"
    assert_includes response.body, "昨日の代理指標を更新"
    assert_includes response.body, "代理指標を期間バックフィル"
    assert_includes response.body, "代理指標から行動候補を生成"
    assert_includes response.body, "proxy_score重み補正"
    assert_includes response.body, "全体重みを補正"
    assert_includes response.body, "全事業の重みを補正"
    assert_includes response.body, "行動結果の採点"
    assert_includes response.body, "評価待ちActionResult"
    assert_includes response.body, "今月利益順"
    business_summary_section = response.body.split("事業別サマリー").last
    assert_operator business_summary_section.index(cards.name), :<, business_summary_section.index(suelog.name)
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

  test "generates action candidates from metrics from dashboard" do
    post generate_action_candidates_from_metrics_dashboard_url

    assert_redirected_to dashboard_url
    assert_match(/代理指標から行動候補を/, flash[:notice])
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

  test "dashboard data preparation task can be sent to executor" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Dashboard data preparation task",
      action_type: "data_preparation",
      generation_source: "ai_business",
      immediate_value_yen: 0,
      success_probability: 0.6,
      expected_hours: 1,
      execution_prompt: "ActionResultを記録してください",
      metadata: {
        "missing_type" => [ "action_results" ],
        "required_count" => { "action_results" => 10 },
        "current_count" => { "action_results" => 0 }
      }
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, action_candidate.title
    assert_includes response.body, "Executorへ送る"
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

  test "shows rule based candidate generation summary" do
    AicooLabExperimentCandidate.create!(
      title: "Generated dashboard candidate",
      description: "Dashboard generated candidate",
      experiment_type: "lp",
      market_category: "dashboard",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 40_000,
      success_probability: 0.3,
      budget_yen: 0,
      estimated_work_minutes: 60,
      assumed_price_yen: 9_800,
      lp_word_count: 800,
      cta_count: 1,
      rationale: "Rule based dashboard summary",
      generation_source: "rule_based"
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "自動生成候補数"
    assert_includes response.body, "直近7日生成候補数"
  end

  test "shows AICOO Lab generation run summary" do
    AicooLabGenerationRun.create!(
      generation_type: "candidate_generation",
      prompt: "Dashboard prompt",
      response: "Dashboard response",
      status: "succeeded",
      generated_count: 3
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "アイデア生成履歴総数"
    assert_includes response.body, "直近7日アイデア生成履歴数"
    assert_includes response.body, "アイデア生成履歴"
  end

  test "shows AICOO Lab AI draft summary" do
    generation_run = AicooLabGenerationRun.create!(
      generation_type: "candidate_generation",
      prompt: "Draft prompt",
      response: JSON.generate(candidates: []),
      status: "succeeded",
      generated_count: 0
    )
    AicooLabAiDraft.create!(
      title: "Dashboard AI draft",
      generation_run:,
      raw_response: generation_run.response,
      parsed_json: { candidates: [] },
      status: "draft"
    )
    AicooLabAiDraft.create!(
      title: "Dashboard imported AI draft",
      generation_run:,
      raw_response: generation_run.response,
      parsed_json: { candidates: [] },
      status: "imported"
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "AI下書き件数"
    assert_includes response.body, "AI承認待ち件数"
    assert_includes response.body, "AI取込済み件数"
    assert_includes response.body, "AI提案"
  end

  test "shows AICOO Revenue execution summary" do
    alert_candidate = AicooLabExperimentCandidate.create!(
      title: "Dashboard neglect alert",
      description: "Dashboard neglect alert",
      experiment_type: "lp",
      market_category: "dashboard",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 40_000,
      success_probability: 0.3,
      budget_yen: 0,
      estimated_work_minutes: 60,
      rationale: "Dashboard neglect alert",
      neglect_loss_90d_yen: 5_000
    )
    alert_candidate.update_columns(updated_at: 15.days.ago)
    AicooRevenueExecution.create!(
      source_type: "candidate",
      source_id: 1,
      title: "Dashboard planned revenue execution",
      expected_90d_profit_yen: 50_000,
      success_probability: 0.2,
      revenue_total_value_yen: 10_000,
      estimated_work_minutes: 60,
      budget_yen: 0,
      revenue_score: 10,
      status: "planned"
    )
    AicooRevenueExecution.create!(
      source_type: "experiment",
      source_id: 2,
      title: "Dashboard done revenue execution",
      expected_90d_profit_yen: 60_000,
      success_probability: 0.3,
      revenue_total_value_yen: 18_000,
      estimated_work_minutes: 90,
      budget_yen: 0,
      revenue_score: 12,
      status: "done",
      done_at: Time.current,
      actual_90d_profit_yen: 12_000
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "今日やることサマリー"
    assert_includes response.body, "今日の期待価値"
    assert_includes response.body, "実行予定数"
    assert_includes response.body, "放置アラート件数"
    assert_includes response.body, "平均予測精度"
    assert_includes response.body, "詳細を見る"
  end

  test "shows AICOO DataHub summary" do
    experiment = AicooLabExperiment.create!(
      title: "Dashboard DataHub scoring",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "running"
    )
    landing_page = experiment.create_aicoo_lab_landing_page!(
      headline: "Dashboard DataHub headline",
      subheadline: "Dashboard DataHub subheadline",
      body: "Dashboard DataHub body",
      cta_text: "事前登録する"
    )
    AicooDataSnapshot.create!(
      source_type: "landing_page",
      source_id: landing_page.id,
      payload: {
        experiment_id: experiment.id,
        pv: 12,
        cta_click: 1,
        signup: 1
      }
    )
    AicooDataHubCollectionRun.create!(
      started_at: 10.minutes.ago,
      finished_at: 5.minutes.ago,
      status: "success",
      snapshot_count: 7
    )
    analytics_setting = AnalyticsSourceSetting.create!(
      source_type: "gsc",
      name: "Dashboard analytics fetch",
      site_url: "sc-domain:suelog.jp"
    )
    analytics_setting.analytics_fetch_runs.create!(
      source_type: "gsc",
      status: "success",
      started_at: 4.minutes.ago,
      finished_at: 3.minutes.ago,
      snapshot_count: 2,
      updated_neglect_loss_count: 1
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "実績データ"
    assert_includes response.body, "取得済み実績データ数"
    assert_includes response.body, "今日取得数"
    assert_includes response.body, "採点候補数"
    assert_includes response.body, "最終収集日時"
    assert_includes response.body, "直近収集件数"
    assert_includes response.body, "Analytics最終取得日時"
    assert_includes response.body, "Analytics直近取得status"
    assert_includes response.body, "Analytics直近取得件数"
    assert_includes response.body, "定期取得準備"
    assert_includes response.body, "実績データを見る"
    assert_includes response.body, "サイト別分析設定"
    assert_includes response.body, "登録サイト数"
    assert_includes response.body, "GSC接続済みサイト数"
    assert_includes response.body, "GA4接続済みサイト数"
    assert_includes response.body, "最終取得成功サイト数"
    assert_not_includes response.body, "Analytics API設定"
    assert_includes response.body, "定期取得コマンド: "
    assert_includes response.body, "bin/rails aicoo:analytics:daily_fetch"
  end

  test "shows prediction source summary" do
    experiment = AicooLabExperiment.create!(
      title: "Prediction source dashboard",
      experiment_type: "lp",
      acquisition_channel: "seo"
    )
    experiment.aicoo_lab_predictions.create!(
      prediction_type: "profit",
      target_days: 90,
      predicted_value: 10_000,
      predicted_value_unit: "yen",
      prediction_source: "lab"
    )
    experiment.aicoo_lab_predictions.create!(
      prediction_type: "pv",
      target_days: 30,
      predicted_value: 100,
      predicted_value_unit: "count",
      prediction_source: "human"
    )
    AicooRevenueExecution.create!(
      source_type: "candidate",
      source_id: 1,
      title: "Prediction source revenue",
      expected_90d_profit_yen: 50_000,
      success_probability: 0.2,
      revenue_total_value_yen: 10_000,
      estimated_work_minutes: 60,
      budget_yen: 0,
      revenue_score: 10,
      status: "planned",
      prediction_source: "revenue"
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "予測者集計"
    assert_includes response.body, "新規事業予測数"
    assert_includes response.body, "今日やること予測数"
    assert_includes response.body, "Human予測数"
  end

  test "dashboard does not show seed data controls" do
    get dashboard_url

    assert_response :success
    assert_not_includes response.body, "仮データ"
    assert_not_includes response.body, "初期サンプル"
  end

  test "shows judge summary" do
    AicooRevenueExecution.create!(
      source_type: "candidate",
      source_id: 10,
      title: "Judge dashboard revenue",
      expected_90d_profit_yen: 50_000,
      success_probability: 0.2,
      revenue_total_value_yen: 10_000,
      estimated_work_minutes: 60,
      budget_yen: 0,
      revenue_score: 10,
      status: "done",
      prediction_source: "revenue",
      actual_90d_profit_yen: 8_000
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "成績表サマリー"
    assert_includes response.body, "採点済み予測数"
    assert_includes response.body, "現在最も当たる予測者"
    assert_includes response.body, "成績表を見る"
    assert_includes response.body, admin_aicoo_judge_path
  end

  test "revenue calibration does not affect lab calibration score" do
    AicooRevenueExecution.create!(
      source_type: "candidate",
      source_id: 1,
      title: "Revenue calibration only",
      expected_90d_profit_yen: 50_000,
      success_probability: 0.2,
      revenue_total_value_yen: 10_000,
      estimated_work_minutes: 60,
      budget_yen: 0,
      revenue_score: 10,
      status: "done",
      actual_90d_profit_yen: 0
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "平均予測精度"
    assert_match(/<span>予測精度<\/span><strong>-<\/strong>/, response.body)
  end

  test "shows preview ready and auto landing page summary" do
    experiment = AicooLabExperiment.create!(
      title: "Preview ready dashboard experiment",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "preview_ready"
    )
    experiment.create_aicoo_lab_landing_page!(
      headline: "Auto LP headline",
      subheadline: "Auto LP subheadline",
      body: "Auto LP body",
      cta_text: "事前登録する",
      status: "preview_ready",
      generation_source: "candidate_conversion"
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "LP作成済み検証数"
    assert_includes response.body, "自動LP作成済み実験数"
  end

  test "shows review queue approval summary" do
    AicooLabExperiment.create!(
      title: "Review queue dashboard",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "preview_ready",
      approval_status: "not_required"
    )
    AicooLabExperiment.create!(
      title: "Approved dashboard",
      experiment_type: "lp",
      acquisition_channel: "seo",
      approval_status: "approved"
    )
    AicooLabExperiment.create!(
      title: "Rejected dashboard",
      experiment_type: "lp",
      acquisition_channel: "seo",
      approval_status: "rejected"
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "レビュー待ち件数"
    assert_includes response.body, "承認待ち件数"
    assert_includes response.body, "approved件数"
    assert_includes response.body, "却下件数"
  end

  test "shows running and scoring due summary" do
    AicooLabExperiment.create!(
      title: "Approved not started dashboard",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "preview_ready",
      approval_status: "approved"
    )
    AicooLabExperiment.create!(
      title: "Running due dashboard",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "running",
      approval_status: "approved",
      score_due_7d_at: 1.day.ago,
      score_due_30d_at: 1.day.ago,
      score_due_90d_at: 1.day.ago
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "approved未開始件数"
    assert_includes response.body, "検証中件数"
    assert_includes response.body, "7日採点待ち件数"
    assert_includes response.body, "30日採点待ち件数"
    assert_includes response.body, "90日採点待ち件数"
  end

  test "shows scoring queue and formal scored summary" do
    experiment = AicooLabExperiment.create!(
      title: "Formal scored dashboard",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "running",
      score_due_7d_at: 1.day.ago
    )
    experiment.aicoo_lab_results.create!(
      result_type: "pv",
      target_days: 90,
      actual_value: 10,
      actual_value_unit: "count",
      sample_size: 10
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "採点待ち件数"
    assert_includes response.body, "正式採点済み実験数"
  end

  test "shows AICOO Lab v1 operation dashboard" do
    candidate = AicooLabExperimentCandidate.create!(
      title: "Today candidate",
      experiment_type: "lp",
      acquisition_channel: "seo",
      expected_90d_profit_yen: 50_000,
      success_probability: 0.4,
      estimated_work_minutes: 60,
      status: "proposed"
    )
    experiment = AicooLabExperiment.create!(
      title: "Today review experiment",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "preview_ready",
      approval_status: "not_required",
      expected_90d_profit_yen: 60_000,
      success_probability: 0.3,
      estimated_work_minutes: 60
    )
    experiment.create_aicoo_lab_landing_page!(
      headline: "Today headline",
      subheadline: "Today subheadline",
      body: "Today body",
      cta_text: "事前登録する",
      status: "preview_ready",
      generation_source: "candidate_conversion"
    )

    get dashboard_url

    assert_response :success
    assert_includes response.body, "新規事業 次アクション"
    assert_includes response.body, "新規事業の流れ"
    assert_includes response.body, "今日やること"
    assert_includes response.body, candidate.title
    assert_includes response.body, "候補を自動生成"
    assert_includes response.body, "レビュー待ち"
    assert_includes response.body, "承認済み未開始"
    assert_includes response.body, "採点待ち"
    assert_includes response.body, "新規事業 KPI"
    assert_includes response.body, "採点済み実験数"
    assert_includes response.body, "予測精度"
    assert_includes response.body, "今月使用額"
    assert_includes response.body, "月予算"
    assert_includes response.body, "実験ライフサイクル"
  end

  test "shows fixed operation steps" do
    get dashboard_url

    assert_response :success
    assert_includes response.body, "新規事業の使い方"
    assert_includes response.body, "候補を作る"
    assert_includes response.body, "良さそうな候補をLP化する"
    assert_includes response.body, "LPを見て承認する"
    assert_includes response.body, "検証開始"
    assert_includes response.body, "LP URLに流入させる"
    assert_includes response.body, "採点して予測誤差を記録する"
  end

  test "shows AICOO Revenue action candidate integration link" do
    get dashboard_url

    assert_response :success
    assert_includes response.body, "今日やること"
    assert_includes response.body, "今日やることサマリー"
    assert_includes response.body, "詳細を見る"
    assert_includes response.body, "実行指示"
    assert_includes response.body, admin_aicoo_executor_path
  end
end
