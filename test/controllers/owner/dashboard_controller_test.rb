require "test_helper"

module Owner
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "balanced mode orders by total expected value" do
      high_total = create_action(title: "総期待値が高い施策", immediate_value_yen: 10_000, action_type: "build_lp")
      low_total = create_action(title: "総期待値が低い施策", immediate_value_yen: 1_000, action_type: "other")

      get owner_dashboard_url(mode: "balanced")

      assert_response :success
      assert_includes response.body, "AICOO CEO MODE"
      assert_includes response.body, "aicoo-owner-secondary"
      assert_includes response.body, "table-wrap"
      assert_includes response.body, "Focus Home"
      assert_includes response.body, "Focusで処理"
      assert_includes response.body, "現在"
      assert_includes response.body, "CEO MODE"
      assert_includes response.body, "SYSTEM MODEへ"
      assert_order high_total.title, low_total.title
      assert_includes response.body, "今日やること TOP10"
      assert_includes response.body, "今日の確認タスク"
      assert_includes response.body, "今日の確認ダイジェスト"
      assert_includes response.body, "Daily Run Health"
      assert_includes response.body, "今日の提案"
      assert_includes response.body, "pending補正"
      assert_includes response.body, "確認タスク一覧へ"
      assert_includes response.body, "期待値"
      assert_includes response.body, "予測精度"
      assert_includes response.body, "Accuracy Score"
      assert_includes response.body, "今週改善"
      assert_includes response.body, "学習品質レポートを見る"
      assert_includes response.body, "Top Opportunities"
      assert_includes response.body, "Top Discovery Sources"
      assert_includes response.body, "Top Explore Signals"
      assert_includes response.body, "Explore Data Hubを見る"
      assert_includes response.body, "新規Import"
      assert_includes response.body, "ExploreをImport"
      assert_includes response.body, "Focus待ち"
      assert_includes response.body, "高score"
      assert_includes response.body, "Observation Focus"
      assert_includes response.body, "Explore Daily Routine"
      assert_includes response.body, "高優先Opportunity"
      assert_includes response.body, "Focus Queue"
      assert_includes response.body, "最優先Opportunity"
      assert_includes response.body, "Opportunityを追加"
      assert_includes response.body, "Opportunitiesを見る"
      assert_includes response.body, "Focusで処理"
      assert_includes response.body, "Discovery Reportを見る"
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
        title: "予測精度の学習価値が高い施策",
        immediate_value_yen: 1_000,
        action_type: "market_research",
        evaluation_reason: "実行結果を増やして予測精度を改善する"
      )

      get owner_dashboard_url(mode: "learning")

      assert_response :success
      assert_order learning_action.title, revenue_action.title
    end

    test "shows owner alerts approval queue and business rankings" do
      action = create_action(title: "承認待ち施策", immediate_value_yen: 5_000, action_type: "build_lp")
      AicooExecutorTask.create!(
        title: "承認待ち実行指示",
        source_type: "action_candidate",
        source_id: action.id,
        execution_type: "custom",
        status: "approval_pending"
      )

      get owner_dashboard_url

      assert_response :success
      assert_includes response.body, "危険アラート"
      assert_includes response.body, "承認待ち"
      assert_includes response.body, "承認済み"
      assert_includes response.body, "確認タスクを見る"
      assert_includes response.body, "今日承認"
      assert_includes response.body, "今日実行指示へ送信"
      assert_includes response.body, "実行承認待ち"
      assert_includes response.body, "事業ランキング"
      assert_includes response.body, "学習状況"
      assert_includes response.body, "AICOO成熟度"
      assert_includes response.body, "日次指標"
      assert_includes response.body, "判断材料の推移"
      assert_includes response.body, "検索流入"
      assert_includes response.body, "前回比"
      assert_includes response.body, businesses(:suelog).name
      assert_not_includes response.body, "実績データ"
      assert_not_includes response.body, "成績表"
    end

    test "shows at least three owner tasks when candidates are empty" do
      ActionCandidate.update_all(status: "archived")

      get owner_dashboard_url

      assert_response :success
      assert_includes response.body, "AICOO推奨タスク"
      assert_operator response.body.scan("<tr>").size, :>=, 3
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
      today_tasks_section = response.body.split("今日やること TOP10").last
      assert_operator today_tasks_section.index(first_text), :<, today_tasks_section.index(second_text)
    end
  end
end
