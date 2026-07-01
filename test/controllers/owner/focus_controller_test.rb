require "test_helper"

module Owner
  class FocusControllerTest < ActionDispatch::IntegrationTest
    setup do
      ActionCandidate.update_all(status: "done")
      AutoRevisionTask.delete_all
    end

    test "shows business improvement ranking instead of system operations" do
      candidate = create_candidate!(
        title: "CTRが低い記事5本のSEOタイトルを改訂する",
        immediate_value_yen: 40_000,
        success_probability: 0.8,
        expected_hours: 1
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "今日の事業改善"
      assert_includes response.body, "今日の1件"
      assert_includes response.body, "今日おすすめの事業改善 TOP10"
      assert_includes response.body, "Businessカード"
      assert_includes response.body, businesses(:suelog).name
      assert_includes response.body, candidate.title
      assert_includes response.body, "AIがこの改善を勧める理由"
      assert_includes response.body, "Codexへ送る"
      assert_includes response.body, "Daily Run Health"
      assert_includes response.body, "改訂待ち"
      assert_includes response.body, "承認待ち改訂"
      assert_includes response.body, "自動デプロイ可能"
      assert_includes response.body, "PR確認待ち"
      assert_includes response.body, "deploy確認待ち"
      assert_not_includes response.body, "SERP走査"
      assert_not_includes response.body, "Cron Ready"
      assert_not_includes response.body, "Google OAuth"
      assert_not_includes response.body, "AICOO Analytics Import"
    end

    test "orders improvements by expected profit before lower value candidates" do
      low = create_candidate!(
        title: "小さい改善",
        immediate_value_yen: 5_000,
        success_probability: 0.5,
        expected_hours: 1
      )
      high = create_candidate!(
        title: "大きい改善",
        immediate_value_yen: 80_000,
        success_probability: 0.9,
        expected_hours: 2
      )

      get owner_focus_url

      assert_response :success
      assert_operator response.body.index(high.title), :<, response.body.index(low.title)
    end

    test "includes auto revision task as codex improvement" do
      candidate = create_candidate!(
        title: "LPのCTAを改善する",
        immediate_value_yen: 30_000,
        success_probability: 0.7,
        expected_hours: 1
      )
      task = AutoRevisionTask.create!(
        business: candidate.business,
        action_candidate: candidate,
        title: "LP CTAをCodexで改善する",
        execution_prompt: "CTA文言を改善してください。",
        status: "waiting_approval",
        risk_level: "low",
        priority_score: 10_000
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, task.title
      assert_includes response.body, export_codex_prompt_auto_revision_task_path(task)
      assert_includes response.body, "承認待ち改訂"
      assert_includes response.body, "1件"
    end

    test "defer hides improvement from current ranking" do
      candidate = create_candidate!(
        title: "後で確認する改善",
        immediate_value_yen: 40_000,
        success_probability: 0.8,
        expected_hours: 1
      )

      patch defer_owner_focus_path(task_key: "action_candidate:#{candidate.id}")
      assert_redirected_to owner_focus_path
      follow_redirect!

      assert_response :success
      assert_not_includes response.body, candidate.title
    end

    test "does not show system business as business card or blocker" do
      system_business = Business.create!(
        name: "AICOO Analytics Import",
        description: "system import holder",
        status: "launched"
      )
      ActionCandidate.create!(
        business: system_business,
        title: "System-only candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 999_999,
        success_probability: 1,
        expected_hours: 1
      )
      create_candidate!(
        title: "通常Business改善",
        immediate_value_yen: 10_000,
        success_probability: 0.8,
        expected_hours: 1
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "通常Business改善"
      assert_not_includes response.body, "AICOO Analytics Import"
      assert_not_includes response.body, "System-only candidate"
    end

    private

    def create_candidate!(attributes)
      ActionCandidate.create!(
        {
          business: businesses(:suelog),
          status: "approved",
          action_type: "seo_improvement",
          evaluation_reason: "CTRが7日平均より低下しています。タイトル改善で利益増加が見込めます。"
        }.merge(attributes)
      )
    end
  end
end
