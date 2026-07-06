require "test_helper"

module Aicoo
  class SuelogSerpContaminationCleanupTest < ActiveSupport::TestCase
    test "archives contaminated suelog candidates and related execution records" do
      business = businesses(:suelog)
      candidate = business.action_candidates.create!(
        title: "吸えログ 比較のSERP差分を埋める",
        description: "it-trend.jp/log_management/article/84-0008 を参考に比較ページを作る",
        action_type: "seo_article",
        generation_source: "integrated_decision",
        status: "idea",
        success_probability: 0.4,
        immediate_value_yen: 20_000,
        expected_hours: 1,
        metadata: {
          "serp_top_results" => [
            { "title" => "ログ管理", "url" => "https://it-trend.jp/log_management/article/84-0008" }
          ]
        }
      )
      execution = candidate.create_action_execution!(status: "ready", execution_type: "manual")
      task = AutoRevisionTask.from_action_candidate(candidate, generated_by: "test")

      result = SuelogSerpContaminationCleanup.call(regenerate: false)

      assert_includes result.archived_action_candidate_ids, candidate.id
      assert_includes result.cancelled_action_execution_ids, execution.id
      assert_includes result.canceled_auto_revision_task_ids, task.id
      assert_equal "archived", candidate.reload.status
      assert_equal "cancelled", execution.reload.status
      assert_equal "canceled", task.reload.status
    end

    test "deduplicates active suelog candidates with same target and action type" do
      business = businesses(:suelog)
      first = business.action_candidates.create!(
        title: "梅田記事のCTAを改善する",
        description: "内部データ由来",
        action_type: "ui_improvement",
        generation_source: "business_analyzer",
        status: "idea",
        success_probability: 0.4,
        immediate_value_yen: 30_000,
        expected_hours: 1,
        metadata: { "target_url" => "/umeda", "data_sources_used" => %w[gsc ga4 internal] }
      )
      second = business.action_candidates.create!(
        title: "梅田記事のCTAを改善する重複",
        description: "内部データ由来",
        action_type: "ui_improvement",
        generation_source: "business_analyzer",
        status: "idea",
        success_probability: 0.2,
        immediate_value_yen: 10_000,
        expected_hours: 1,
        metadata: { "target_url" => "/umeda", "data_sources_used" => %w[gsc ga4 internal] }
      )

      result = SuelogSerpContaminationCleanup.call(regenerate: false)

      assert_includes result.deduplicated_action_candidate_ids, second.id
      assert_equal "idea", first.reload.status
      assert_equal "archived", second.reload.status
    end
  end
end
