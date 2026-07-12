require "test_helper"

module Admin
  class AicooRevenueControllerTest < ActionDispatch::IntegrationTest
    setup do
      AicooDailyRunStep.delete_all
      AicooDailyRun.delete_all
    end

    test "shows Today as ranked action list with three modes" do
      candidate = create_today_candidate(
        title: "梅田の未確認店舗を30件確認済みにする",
        execution_mode: "manual_operation",
        immediate_value_yen: 20_000,
        success_probability: 0.8,
        expected_hours: 1.5
      )

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "Today"
      assert_includes response.body, Aicoo::TodayActionBoard::DESCRIPTION
      assert_includes response.body, "収益優先"
      assert_includes response.body, "学習優先"
      assert_includes response.body, "バランス"
      assert_includes response.body, "今日処理するAction"
      assert_includes response.body, "梅田の未確認店舗を30件確認済みにする"
      assert_includes response.body, "手作業"
      assert_includes response.body, action_workspace_path(candidate)
      assert_not_includes response.body, "今日の結論"
      assert_not_includes response.body, "今日使える時間"
      assert_not_includes response.body, business_path(candidate.business)
    end

    test "shows code revision that has not been executed yet" do
      candidate = create_today_candidate(
        title: "CTA表示文言を修正する",
        execution_mode: "code_revision",
        immediate_value_yen: 30_000,
        success_probability: 0.8,
        expected_hours: 1
      )
      AutoRevisionTask.create!(
        action_candidate: candidate,
        business: candidate.business,
        title: candidate.title,
        status: "ready_for_codex",
        risk_level: "low",
        priority_score: 10
      )

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "CTA表示文言を修正する"
      assert_includes response.body, action_workspace_path(candidate)
    end

    test "shows code revision waiting for owner judgment with approval reason" do
      candidate = create_today_candidate(
        title: "認証まわりの改修を確認する",
        execution_mode: "code_revision",
        immediate_value_yen: 40_000,
        success_probability: 0.5,
        expected_hours: 2
      )
      AutoRevisionTask.create!(
        action_candidate: candidate,
        business: candidate.business,
        title: candidate.title,
        status: "waiting_approval",
        risk_level: "high",
        priority_score: 10
      )

      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "認証まわりの改修を確認する"
      assert_includes response.body, "Codex改修"
      assert_includes response.body, "必要"
      assert_includes response.body, "はい"
      assert_includes response.body, "高リスク改修のためOwner判断が必要です。"
      assert_includes response.body, action_workspace_path(candidate)
    end

    test "does not show unspecified target or missing execution units" do
      create_today_candidate(
        title: "対象未特定の作業",
        execution_mode: "manual_operation",
        target: "未特定",
        execution_units: [ { "label" => "対象を確認する", "estimated_minutes" => 10 } ]
      )
      create_today_candidate(
        title: "実行単位なしの作業",
        execution_mode: "data_operation",
        execution_units: []
      )

      get admin_aicoo_revenue_url

      assert_response :success
      assert_not_includes response.body, "対象未特定の作業"
      assert_not_includes response.body, "実行単位なしの作業"
    end

    test "does not show abstract action" do
      create_today_candidate(
        title: "CVを改善する",
        concrete_task: "CVを改善する",
        execution_mode: "manual_operation"
      )

      get admin_aicoo_revenue_url

      assert_response :success
      assert_not_includes response.body, "CVを改善する"
    end

    test "learning mode ranks by learning values" do
      revenue_first = create_today_candidate(
        title: "収益が高い作業",
        execution_mode: "manual_operation",
        immediate_value_yen: 80_000,
        success_probability: 0.8,
        expected_hours: 1,
        metadata_overrides: { "learning_value" => 10 }
      )
      learning_first = create_today_candidate(
        title: "学習価値が高い作業",
        execution_mode: "content_creation",
        immediate_value_yen: 5_000,
        success_probability: 0.3,
        expected_hours: 1,
        metadata_overrides: { "learning_value" => 500_000, "uncertainty_reduction" => 100_000 }
      )

      get admin_aicoo_revenue_url, params: { mode: "learning" }

      assert_response :success
      body = response.body
      assert_operator body.index("学習価値が高い作業"), :<, body.index("収益が高い作業")
      assert_includes body, action_workspace_path(learning_first)
      assert_includes body, action_workspace_path(revenue_first)
    end

    test "empty state does not show business dashboard content" do
      get admin_aicoo_revenue_url

      assert_response :success
      assert_includes response.body, "Todayに表示するActionはありません"
      assert_not_includes response.body, "Business概要"
      assert_not_includes response.body, "詳細ランキングを見る"
    end

    private

    def create_today_candidate(attributes = {})
      business = Business.create!(name: attributes.delete(:business_name) || "Today Test Business")
      execution_mode = attributes.delete(:execution_mode) || "manual_operation"
      target = attributes.delete(:target) || "梅田エリア / 未確認店舗30件"
      concrete_task = attributes.delete(:concrete_task) || attributes[:title] || "梅田の未確認店舗を30件確認済みにする"
      execution_units = attributes.delete(:execution_units)
      execution_units = [
        {
          "label" => concrete_task,
          "area" => "梅田",
          "target_amount" => 30,
          "estimated_minutes" => 90,
          "reason" => "確認済み率が低いため"
        }
      ] if execution_units.nil?
      metadata_overrides = attributes.delete(:metadata_overrides) || {}
      action_plan = {
        "summary" => concrete_task,
        "target" => target,
        "execution_mode" => execution_mode,
        "owner_next_step" => execution_units.first.to_h["label"].presence || "作業を開始する",
        "execution_steps" => [ "対象一覧取得", "作業実行", "ActionResult登録" ],
        "execution_units" => execution_units
      }

      ActionCandidate.create!(
        {
          business:,
          title: concrete_task,
          action_type: "seo_improvement",
          status: "idea",
          generation_source: "business_analyzer",
          immediate_value_yen: 20_000,
          success_probability: 0.8,
          expected_hours: 1.5,
          cost_yen: 0,
          metadata: {
            "execution_mode" => execution_mode,
            "action_plan" => action_plan,
            "execution_units" => execution_units,
            "evidence" => {
              "source" => [ "gsc", "business_db" ],
              "area" => "梅田",
              "target_amount" => 30,
              "reason" => "根拠データに基づく作業"
            }
          }.merge(metadata_overrides)
        }.merge(attributes)
      )
    end
  end
end
