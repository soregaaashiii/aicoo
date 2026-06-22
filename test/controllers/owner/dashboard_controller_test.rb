require "test_helper"

module Owner
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "balanced mode orders by total expected value" do
      high_total = create_action(title: "総期待値が高い施策", immediate_value_yen: 10_000, action_type: "build_lp")
      low_total = create_action(title: "総期待値が低い施策", immediate_value_yen: 1_000, action_type: "other")

      get owner_dashboard_url(mode: "balanced")

      assert_response :success
      assert_order high_total.title, low_total.title
      assert_includes response.body, "今日やること TOP10"
      assert_includes response.body, "期待値"
    end

    test "revenue mode orders by revenue value" do
      revenue_action = create_action(title: "収益価値が高い施策", immediate_value_yen: 30_000, action_type: "other")
      learning_action = create_action(title: "学習価値が高い施策", immediate_value_yen: 1_000, action_type: "market_research")

      get owner_dashboard_url(mode: "revenue")

      assert_response :success
      assert_order revenue_action.title, learning_action.title
    end

    test "learning mode orders by learning value" do
      revenue_action = create_action(title: "収益だけ高い施策", immediate_value_yen: 30_000, action_type: "other", data_confidence_score: 100)
      learning_action = create_action(
        title: "Judge学習価値が高い施策",
        immediate_value_yen: 1_000,
        action_type: "market_research",
        evaluation_reason: "ActionResultを増やしてJudgeの予測精度を改善する"
      )

      get owner_dashboard_url(mode: "learning")

      assert_response :success
      assert_order learning_action.title, revenue_action.title
    end

    test "shows owner alerts approval queue and business rankings" do
      action = create_action(title: "承認待ち施策", immediate_value_yen: 5_000, action_type: "build_lp")
      AicooExecutorTask.create!(
        title: "承認待ちExecutor",
        source_type: "action_candidate",
        source_id: action.id,
        execution_type: "custom",
        status: "approval_pending"
      )

      get owner_dashboard_url

      assert_response :success
      assert_includes response.body, "危険アラート"
      assert_includes response.body, "承認待ち"
      assert_includes response.body, "承認済みキュー"
      assert_includes response.body, "今日承認"
      assert_includes response.body, "今日Executor送信"
      assert_includes response.body, "ExecutorTask approval_pending"
      assert_includes response.body, "事業ランキング"
      assert_includes response.body, businesses(:suelog).name
    end

    test "can approve action candidate from owner dashboard" do
      action = create_action(title: "Owner承認施策", immediate_value_yen: 5_000)

      patch approve_action_candidate_url(action)

      assert_redirected_to owner_dashboard_url
      assert_equal "approved", action.reload.status
      assert action.approved_at.present?
      assert_equal "owner", action.approved_by
    end

    private

    def create_action(attributes = {})
      ActionCandidate.create!(
        {
          business: businesses(:suelog),
          title: "Owner action",
          action_type: "other",
          status: "idea",
          immediate_value_yen: 1_000,
          success_probability: 1,
          expected_hours: 1,
          cost_yen: 0,
          confidence_score: 78,
          data_confidence_score: 80
        }.merge(attributes)
      )
    end

    def assert_order(first_text, second_text)
      assert_operator response.body.index(first_text), :<, response.body.index(second_text)
    end
  end
end
