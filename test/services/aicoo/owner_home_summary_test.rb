require "test_helper"

module Aicoo
  class OwnerHomeSummaryTest < ActiveSupport::TestCase
    setup do
      ActionExecution.delete_all
      ActionResult.delete_all
      ActionCandidate.update_all(status: "done")
      AicooDailyRunStep.delete_all
      AicooDailyRun.delete_all
      ActionPredictionCalibration.delete_all
      OpportunityDiscoveryItem.delete_all
      ExploreObservation.delete_all
      ExploreImportLog.create!(source_type: "google_trends", import_format: "csv", imported_count: 1)
    end

    test "summarizes next action and counts" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Owner home execution",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1,
        metadata: {
          "execution_mode" => "manual_operation",
          "concrete_task" => "Owner home execution",
          "action_plan" => {
            "summary" => "Owner home execution",
            "target" => "Owner Home",
            "owner_next_step" => "実行する",
            "execution_steps" => [ "実行する" ],
            "execution_units" => [ { "label" => "実行する" } ]
          }
        }
      )
      candidate.create_action_execution!(status: "ready", execution_type: "manual")
      ActionPredictionCalibration.create!(
        action_type: "seo_improvement",
        sample_count: 10,
        approval_status: "pending",
        warning_level: "warning",
        profit_calibration_factor: 1,
        probability_calibration_factor: 1
      )

      summary = OwnerHomeSummary.new.call

      assert_equal "action_candidate:#{candidate.id}", summary.next_action.stable_id
      assert_equal 1, summary.execution_ready_count
      assert_equal 0, summary.result_registration_count
      assert_equal 1, summary.pending_calibration_count
      assert_equal 0, summary.explore_review_count
      assert_equal 0, summary.pending_opportunities_count
      assert_nil summary.top_pending_opportunity
      assert_equal 0, summary.today_queue_count
      assert_equal 0, summary.today_queue_completed_count
      assert_nil summary.top_queue_item
      assert_includes %w[Healthy Warning Critical], summary.daily_run_status
      assert_includes %w[Improving Stable Declining], summary.learning_status
      assert_equal "Todayの最上位Actionを処理してください。", summary.summary_message
    end

    test "summarizes pending opportunities" do
      opportunity = OpportunityDiscoveryItem.create!(
        title: "Explore pending opportunity",
        status: "pending",
        expected_value_yen: 90_000,
        confidence: 80,
        opportunity_score: 85
      )

      summary = OwnerHomeSummary.new.call

      assert_equal 1, summary.pending_opportunities_count
      assert_equal 1, summary.explore_review_count
      assert_equal opportunity, summary.top_pending_opportunity
      assert_nil summary.next_action
    end

    test "uses queue item as next action when focus tasks are empty" do
      ActionCandidate.update_all(status: "done")
      item = OwnerExecutionQueueItem.create!(
        item_type: "opportunity",
        item_id: 1,
        title: "Queue next action",
        risk_level: "low",
        status: "pending",
        due_on: Date.current,
        priority_score: 100
      )

      summary = OwnerHomeSummary.new.call

      assert_equal 1, summary.today_queue_count
      assert_equal item, summary.top_queue_item
      assert_equal item, summary.next_action
      assert_includes summary.summary_message, "今日の実行キュー"
    end
  end
end
