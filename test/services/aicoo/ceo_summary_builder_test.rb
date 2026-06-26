require "test_helper"

module Aicoo
  class CeoSummaryBuilderTest < ActiveSupport::TestCase
    test "converts abstract ranking improvement into owner facing instruction" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "とり友 梅田 の順位改善",
        action_type: "seo_improvement",
        expected_hours: 1,
        success_probability: 0.6,
        immediate_value_yen: 20_000,
        execution_prompt: "順位改善してください。"
      )
      candidate.update_column(
        :metadata,
        candidate.metadata.merge(
          "evidence" => {
            "summary" => [ "表示回数 +42%", "CTR 1.6%", "順位 11位" ]
          },
          "action_expansion" => {
            "expanded" => true,
            "recommended_tasks" => [ "SEOタイトル改訂", "内部リンク追加" ],
            "target" => "とり友 梅田ページ",
            "target_keyword" => "とり友 梅田 喫煙",
            "expected_minutes" => 30,
            "completion_criteria" => [ "タイトル変更完了", "内部リンク3件追加" ]
          }
        )
      )

      summary = CeoSummaryBuilder.new(action_candidate: candidate.reload).call

      assert_equal "とり友 梅田ページでSEOタイトル改訂を行う", summary.title
      assert_not_includes summary.title, "順位改善"
      assert_not_includes summary.title, "ActionCandidate"
      assert_includes summary.reason_lines.join(" "), "表示回数 +42%"
      assert_includes summary.work_lines.join(" "), "とり友 梅田ページ"
      assert_includes summary.work_lines.join(" "), "とり友 梅田 喫煙"
      assert_includes summary.time_lines.join(" "), "SEOタイトル改訂"
      assert_includes summary.completion_criteria, "内部リンク3件追加"
      assert_equal 30, summary.total_minutes
    end

    test "sanitizes internal task names" do
      task = OwnerTaskInbox::Task.new(
        priority: "medium",
        task_type: "action_execution_ready",
        title: "Analytics Import ActionCandidate",
        description: "Generation Sourceを確認",
        target_label: "AICOO",
        target_path: "/dashboard",
        reason: "metadata Builder",
        created_at: Time.current,
        quick_actions: []
      )

      summary = CeoSummaryBuilder.new(task:).call

      assert_not_includes summary.title, "Analytics Import"
      assert_not_includes summary.title, "ActionCandidate"
      assert_not_includes summary.reason_lines.join(" "), "metadata"
    end

    test "uses dedicated system template for daily run failures" do
      task = OwnerTaskInbox::Task.new(
        priority: "critical",
        task_type: "daily_run_failure",
        title: "Daily Run stuck",
        description: "running",
        target_label: "AICOO",
        target_path: "/aicoo_daily_runs/1",
        reason: "critical stuck",
        created_at: Time.current,
        quick_actions: []
      )

      summary = CeoSummaryBuilder.new(task:).call

      assert_equal "自動巡回を再開する", summary.title
      assert_includes summary.reason_lines.join(" "), "自動巡回が止まっています"
      assert_includes summary.work_lines.join(" "), "再実行する"
      assert_nil summary.roi
      assert_not_includes summary.title, "stuck"
      assert_not_includes summary.reason_lines.join(" "), "critical"
    end

    test "removes owner facing internal words" do
      text = CeoSummaryBuilder.human_label("Analytics Import ActionCandidate metadata Generation Source ROI")

      assert_not_includes text, "Analytics Import"
      assert_not_includes text, "ActionCandidate"
      assert_not_includes text, "metadata"
      assert_not_includes text, "Generation Source"
      assert_includes text, "費用対効果"
    end

    test "uses business specific wording for saas and media businesses" do
      media_candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "SEO改善",
        action_type: "seo_improvement",
        metadata: {}
      )
      saas_candidate = ActionCandidate.new(
        business: businesses(:cards),
        title: "UI改善",
        action_type: "ui_improvement",
        metadata: {}
      )

      media_summary = CeoSummaryBuilder.new(action_candidate: media_candidate).call
      saas_summary = CeoSummaryBuilder.new(action_candidate: saas_candidate).call

      assert_includes media_summary.title, "検索流入"
      assert_includes saas_summary.title, "オンボーディング"
    end
  end
end
