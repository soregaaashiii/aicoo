require "test_helper"

module Admin
  class AicooRevenueControllerTest < ActionDispatch::IntegrationTest
    test "shows revenue dashboard" do
      create_candidate(title: "Dashboard revenue candidate")

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "今日やるべきこと"
      assert_includes response.body, "今日使える時間と予算を入力すると"
      assert_includes response.body, "今日使える時間"
      assert_includes response.body, "収益優先度ランキング"
      assert_includes response.body, "期待時給ランキング"
      assert_includes response.body, "投資効率ランキング"
      assert_includes response.body, "今日の結論"
      assert_includes response.body, "この画面でやること"
      assert_includes response.body, "Labとの違い"
      assert_includes response.body, "実行予定にする"
      assert_includes response.body, "aicoo-sub-tabs"
      assert_includes response.body, "実行予定"
      assert_includes response.body, "実行済み"
      assert_includes response.body, "採点済み"
      assert_includes response.body, "操作盤"
      assert_includes response.body, "Dashboard revenue candidate"
      assert_includes response.body, "攻め: 実行したら増える期待利益"
      assert_includes response.body, "新規事業は学習量を最大化します"
      assert_includes response.body, "詳細ランキングを見る"
      assert_includes response.body, "合計期待価値"
      assert_includes response.body, "放置アラート"
    end

    test "shows candidates and experiments" do
      create_candidate(title: "Controller revenue candidate")
      create_experiment(title: "Controller revenue experiment")
      create_action_candidate(title: "Controller revenue action")

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "Controller revenue candidate"
      assert_includes response.body, "Controller revenue experiment"
      assert_includes response.body, "Controller revenue action"
      assert_includes response.body, "candidate"
      assert_includes response.body, "experiment"
      assert_includes response.body, "行動候補"
    end

    test "filters by minutes and budget params" do
      create_candidate(title: "Visible revenue row", estimated_work_minutes: 60, budget_yen: 0)
      create_candidate(title: "Hidden by time row", estimated_work_minutes: 240, budget_yen: 0)
      create_candidate(title: "Hidden by budget row", estimated_work_minutes: 60, budget_yen: 1_000)

      get admin_aicoo_revenue_url, params: { available_minutes: 120, available_budget_yen: 500 }

      assert_response :success
      assert_includes response.body, "Visible revenue row"
      assert_not_includes response.body, "Hidden by time row"
      assert_not_includes response.body, "Hidden by budget row"
    end

    test "shows free cost for zero budget roi" do
      create_candidate(title: "Zero budget revenue", budget_yen: 0)

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "Zero budget revenue"
      assert_includes response.body, "費用なし"
    end

    test "filters by source" do
      create_candidate(title: "Source lab candidate")
      create_experiment(title: "Source lab experiment")
      create_action_candidate(title: "Source action candidate")

      get admin_aicoo_revenue_url, params: { source: "action_candidate" }

      assert_response :success
      assert_includes response.body, "Source action candidate"
      assert_not_includes response.body, "Source lab candidate"
      assert_not_includes response.body, "Source lab experiment"
    end

    test "today conclusion shows top candidate within constraints" do
      create_candidate(
        title: "Inbox top revenue action",
        expected_90d_profit_yen: 100_000,
        success_probability: 0.5,
        neglect_loss_90d_yen: 20_000,
        estimated_work_minutes: 60,
        budget_yen: 0
      )
      create_candidate(
        title: "Inbox hidden by budget",
        expected_90d_profit_yen: 500_000,
        success_probability: 0.9,
        estimated_work_minutes: 60,
        budget_yen: 10_000
      )

      get admin_aicoo_revenue_url, params: { available_minutes: 120, available_budget_yen: 0 }

      assert_response :success
      assert_includes response.body, "今日の結論"
      assert_includes response.body, "今日はこの順番で実行してください"
      assert_includes response.body, "Inbox top revenue action"
      assert_not_includes response.body, "Inbox hidden by budget"
      assert_includes response.body, "合計期待価値"
      assert_includes response.body, "収益優先度"
      assert_includes response.body, "開く"
    end

    test "detail rankings are collapsed and keep revenue order" do
      create_candidate(title: "Revenue rank 1", expected_90d_profit_yen: 120_000, success_probability: 0.5, neglect_loss_90d_yen: 10_000)
      create_candidate(title: "Revenue rank 2", expected_90d_profit_yen: 90_000, success_probability: 0.5, neglect_loss_90d_yen: 5_000)
      create_candidate(title: "Revenue rank 3", expected_90d_profit_yen: 60_000, success_probability: 0.5, neglect_loss_90d_yen: 4_000)

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "<summary>詳細ランキングを見る</summary>"
      ranking_section = response.body.match(/<h2>収益優先度ランキング<\/h2>.*?<h2>期待時給ランキング<\/h2>/m)[0]

      assert_operator ranking_section.index("Revenue rank 1"), :<, ranking_section.index("Revenue rank 2")
      assert_operator ranking_section.index("Revenue rank 2"), :<, ranking_section.index("Revenue rank 3")
      assert_includes ranking_section, "攻め利益"
      assert_includes ranking_section, "合計期待価値"
      assert_includes ranking_section, "収益優先度"
    end

    test "shows neglect alert panel and badges" do
      candidate = create_candidate(
        title: "Controller neglect alert",
        neglect_loss_90d_yen: 15_000,
        neglect_loss_reason: "放置による失注リスク"
      )
      candidate.update_columns(updated_at: 20.days.ago)

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "放置損失が設定されていて、14日以上更新されていない候補です"
      assert_includes response.body, "Controller neglect alert"
      assert_includes response.body, "放置注意"
      assert_includes response.body, "20日"
      assert_includes response.body, "放置による失注リスク"
    end

    test "shows manual estimated and adopted neglect loss values" do
      action = create_action_candidate(title: "Controller estimated neglect", immediate_value_yen: 100_000, success_probability: 0.5)
      create_gsc_snapshot(action.business, clicks: 100, impressions: 1_000, position: 2, captured_at: 2.days.ago)
      create_gsc_snapshot(action.business, clicks: 40, impressions: 800, position: 7, captured_at: 1.day.ago)

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "Controller estimated neglect"
      assert_includes response.body, "手入力放置損失"
      assert_includes response.body, "自動推定放置損失"
      assert_includes response.body, "採用値"
      assert_includes response.body, "auto_generated"
      assert_includes response.body, "実績データから自動推定した放置損失"
    end


    test "shows today optimal plan within constraints" do
      create_candidate(title: "Plan controller first", expected_90d_profit_yen: 120_000, success_probability: 0.5, estimated_work_minutes: 60, budget_yen: 0)
      create_candidate(title: "Plan controller second", expected_90d_profit_yen: 80_000, success_probability: 0.5, estimated_work_minutes: 60, budget_yen: 300)
      create_candidate(title: "Plan controller hidden by budget", expected_90d_profit_yen: 500_000, success_probability: 0.9, estimated_work_minutes: 60, budget_yen: 1_000)

      get admin_aicoo_revenue_url, params: { available_minutes: 120, available_budget_yen: 300 }

      assert_response :success
      conclusion_section = response.body.match(/<h2>今日の結論<\/h2>.*?<strong>この画面でやること<\/strong>/m)[0]

      assert_includes response.body, "今日はこの順番で実行してください"
      assert_includes conclusion_section, "合計必要時間"
      assert_includes conclusion_section, "合計期待価値"
      assert_includes conclusion_section, "放置損失回避額"
      assert_includes conclusion_section, "Plan controller first"
      assert_includes conclusion_section, "Plan controller second"
      assert_not_includes conclusion_section, "Plan controller hidden by budget"
      assert_includes response.body, "収益優先度ランキング"
    end

    test "shows planned badge when revenue row is already planned" do
      candidate = create_candidate(title: "Already planned revenue row")
      AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: candidate.id,
        title: candidate.title,
        expected_90d_profit_yen: candidate.expected_90d_profit_yen,
        success_probability: candidate.success_probability,
        revenue_total_value_yen: 12_500,
        estimated_work_minutes: candidate.estimated_work_minutes,
        budget_yen: candidate.budget_yen,
        revenue_score: 10,
        status: "planned"
      )

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "Already planned revenue row"
      assert_includes response.body, "実行予定済み"
    end

    test "shows empty optimal plan message" do
      create_candidate(title: "Plan impossible", estimated_work_minutes: 60, budget_yen: 100)

      get admin_aicoo_revenue_url, params: { available_minutes: 30, available_budget_yen: 0 }

      assert_response :success
      assert_includes response.body, "今日の条件で実行できる候補はありません"
      assert_includes response.body, "収益優先度ランキング"
    end

    private

    def create_candidate(attributes = {})
      AicooLabExperimentCandidate.create!(
        {
          title: "Revenue candidate",
          description: "Revenue candidate description",
          experiment_type: "lp",
          market_category: "revenue market",
          acquisition_channel: "seo",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          budget_yen: 0,
          estimated_work_minutes: 60,
          rationale: "Revenue rationale"
        }.merge(attributes)
      )
    end

    def create_experiment(attributes = {})
      AicooLabExperiment.create!(
        {
          title: "Revenue experiment",
          description: "Revenue experiment description",
          experiment_type: "lp",
          market_category: "revenue market",
          acquisition_channel: "seo",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          budget_yen: 0,
          estimated_work_minutes: 60
        }.merge(attributes)
      )
    end

    def create_action_candidate(attributes = {})
      business = Business.create!(name: "Controller revenue business")
      ActionCandidate.create!(
        {
          business:,
          title: "Revenue action candidate",
          action_type: "seo_article",
          status: "idea",
          immediate_value_yen: 80_000,
          success_probability: 0.25,
          expected_hours: 1,
          cost_yen: 0
        }.merge(attributes)
      )
    end

    def create_gsc_snapshot(business, clicks:, impressions:, position:, captured_at:)
      AicooDataSnapshot.create!(
        source_type: "gsc",
        source_id: AicooDataSnapshot.maximum(:source_id).to_i + 1,
        captured_at:,
        payload: {
          business_id: business.id,
          metrics: {
            clicks:,
            impressions:,
            ctr: clicks.to_d / impressions.to_d,
            position:
          }
        }
      )
    end
  end
end
