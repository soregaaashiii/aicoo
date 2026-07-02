require "test_helper"

module Aicoo
  class BusinessPlaybookBuilderTest < ActiveSupport::TestCase
    test "creates business playbook with action type summary" do
      business = businesses(:suelog)
      candidate = ActionCandidate.create!(
        business:,
        title: "Playbook SEO candidate",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 2,
        execution_prompt: "CTR2%未満の記事5本をタイトル改訂してください。"
      )
      ActionResult.create!(
        action_candidate: candidate,
        business:,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        actual_profit_yen: 8_000,
        actual_sessions_delta: 100,
        actual_pageviews_delta: 180,
        metadata: {
          "engagement" => {
            "average_engagement_time_delta_seconds" => 24,
            "views_per_session_delta" => 0.35,
            "conversion_rate_delta" => 0.02
          }
        }
      )
      OwnerDecisionLog.record!(
        subject: candidate,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        previous_status: "idea",
        new_status: "approved"
      )

      playbook = BusinessPlaybookBuilder.new(business).update!

      assert_predicate playbook, :persisted?
      assert_equal business, playbook.business
      assert_operator playbook.sample_count, :>, 0
      assert_operator playbook.confidence_score, :>, 0
      assert_equal "seo_improvement", playbook.top_action_type
      assert playbook.action_type_summary.key?("seo_improvement")
      row = playbook.action_type_summary.fetch("seo_improvement")
      assert_equal "24.0", row.fetch("average_engagement_delta")
      assert_equal "0.35", row.fetch("average_navigation_delta")
      assert_equal "0.02", row.fetch("average_conversion_delta")
      type_summary = playbook.metadata.fetch("business_type_action_summary")
      assert_equal "seo_media", playbook.metadata.fetch("business_type")
      assert type_summary.key?("seo_improvement")
      assert_equal "seo_media", type_summary.fetch("seo_improvement").fetch("business_type")
    end

    test "learns action expansion task performance" do
      business = businesses(:suelog)
      candidate = ActionCandidate.create!(
        business:,
        title: "Expansion learning candidate",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 2,
        execution_prompt: "CTR2%未満の記事5本をタイトル改訂してください。"
      )
      candidate.update_column(
        :metadata,
        {
          "action_expansion" => {
            "version" => "v1",
            "recommended_tasks" => [ "SEOタイトル改訂", "内部リンク追加" ],
            "generated_tasks" => [
              { "name" => "SEOタイトル改訂", "priority" => 1 },
              { "name" => "内部リンク追加", "priority" => 2 }
            ]
          }
        }
      )
      ActionResult.create!(
        action_candidate: candidate,
        business:,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        actual_profit_yen: 12_000,
        metadata: {
          "engagement" => {
            "average_engagement_time_delta_seconds" => 18,
            "views_per_session_delta" => 0.2,
            "conversion_rate_delta" => 0.01
          },
          "action_expansion_learning" => {
            "available_tasks" => [ "SEOタイトル改訂", "内部リンク追加" ],
            "executed_tasks" => [ "SEOタイトル改訂" ],
            "skipped_tasks" => [ "内部リンク追加" ]
          }
        }
      )
      OwnerDecisionLog.record!(
        subject: candidate,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        previous_status: "idea",
        new_status: "approved"
      )

      playbook = BusinessPlaybookBuilder.new(business).update!
      task_summary = playbook.metadata["task_summary"]

      assert task_summary.key?("SEOタイトル改訂")
      assert_equal 1, task_summary["SEOタイトル改訂"]["executed_result_count"].to_i
      assert_operator task_summary["SEOタイトル改訂"]["success_rate"].to_d, :>, 0
      assert_equal "18.0", task_summary["SEOタイトル改訂"]["average_engagement_delta"]
      assert_equal "SEOタイトル改訂", playbook.metadata["recommended_tasks"].first
    end

    test "learns analysis source performance" do
      business = businesses(:suelog)
      business.analysis_candidates.create!(
        analysis_source: "serp",
        status: "completed",
        expected_value_yen: 2_000,
        estimated_cost_yen: 20,
        estimated_minutes: 30,
        roi: 100,
        confidence: 80,
        priority: 90,
        execution_mode: "manual",
        due_on: Date.current,
        reason: "順位急落のためSERP分析"
      )

      playbook = BusinessPlaybookBuilder.new(business).update!
      analysis_summary = playbook.metadata["analysis_summary"]

      assert analysis_summary.key?("serp")
      assert_equal 1, analysis_summary["serp"]["candidate_count"].to_i
      assert_operator analysis_summary["serp"]["roi"].to_d, :>, 0
      assert_equal "serp", playbook.analysis_rows.first["source"]
    end

    test "updates all businesses" do
      result = BusinessPlaybookBuilder.update_all!

      assert_equal Business.count, result.updated_count
      assert_equal Business.count, BusinessPlaybook.count
    end
  end
end
