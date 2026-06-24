require "test_helper"

module Aicoo
  class OwnerHomeSummaryTest < ActiveSupport::TestCase
    setup do
      ActionExecution.delete_all
      ActionResult.delete_all
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
        expected_hours: 1
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

      summary = OwnerHomeSummary.new(owner_focus_home: OwnerFocusHome.new.call).call

      assert_equal "action_execution_ready", summary.next_action.task_type
      assert_equal 1, summary.execution_ready_count
      assert_equal 0, summary.result_registration_count
      assert_equal 1, summary.pending_calibration_count
      assert_equal 0, summary.explore_review_count
      assert_includes %w[Healthy Warning Critical], summary.daily_run_status
      assert_includes %w[Improving Stable Declining], summary.learning_status
      assert_equal "今はこの1件だけ処理してください。", summary.summary_message
    end
  end
end
