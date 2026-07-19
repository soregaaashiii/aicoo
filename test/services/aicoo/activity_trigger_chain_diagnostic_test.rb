require "test_helper"

module Aicoo
  class ActivityTriggerChainDiagnosticTest < ActiveSupport::TestCase
    test "reports the complete after commit trigger chain" do
      activity_log = create_activity("trigger-chain-complete")
      activity_log.update_columns(
        metadata: {
          "activity_evaluation_trigger_chain" => {
            "record_created" => true,
            "after_create_called" => true,
            "after_commit_called" => true,
            "after_commit_skipped" => false,
            "trigger_registered" => true,
            "trigger_called" => true,
            "trigger_completed" => true,
            "builder_called" => true,
            "builder_completed" => true,
            "return_point" => "completed"
          }
        }
      )

      result = ActivityTriggerChainDiagnostic.new(business_id: activity_log.business_id).call
      row = result.rows.find { |item| item.event_id == activity_log.id }

      assert_equal true, row.record_created
      assert_equal true, row.after_create_called
      assert_equal true, row.after_commit_called
      assert_equal false, row.after_commit_skipped
      assert_equal true, row.trigger_registered
      assert_equal true, row.trigger_called
      assert_equal true, row.builder_called
      assert_equal true, row.builder_completed
      assert_equal "completed", row.return_point
      assert_nil row.skip_reason
    end

    test "reports records created before the trigger callback" do
      activity_log = create_activity("trigger-chain-missing")
      activity_log.update_columns(metadata: {})

      result = ActivityTriggerChainDiagnostic.new(business_id: activity_log.business_id).call
      row = result.rows.find { |item| item.event_id == activity_log.id }

      assert_equal true, row.record_created
      assert_equal false, row.after_create_called
      assert_equal false, row.after_commit_called
      assert_equal true, row.after_commit_skipped
      assert_equal false, row.trigger_registered
      assert_equal false, row.trigger_called
      assert_equal false, row.builder_called
      assert_equal "record_committed_without_trigger", row.return_point
      assert_equal "activity_evaluation_trigger_not_called", row.skip_reason
    end

    test "recognizes evaluations created by the legacy builder" do
      activity_log = create_activity("trigger-chain-legacy")
      activity_log.update_columns(metadata: {})
      ActivityEvaluation.create!(
        business: activity_log.business,
        business_activity_log: activity_log,
        evaluation_window_days: 7,
        status: "pending"
      )

      result = ActivityTriggerChainDiagnostic.new(business_id: activity_log.business_id).call
      row = result.rows.find { |item| item.event_id == activity_log.id }

      assert_equal true, row.trigger_registered
      assert_equal true, row.trigger_called
      assert_equal true, row.trigger_completed
      assert_equal true, row.builder_called
      assert_equal true, row.builder_completed
      assert_equal "legacy_builder_completed", row.return_point
      assert_nil row.skip_reason
    end

    private

    def create_activity(key)
      ActivityEvaluationTrigger.stub(:call, nil) do
        BusinessActivityLog.create!(
          business: businesses(:suelog),
          source_app: "suelog",
          activity_type: "article_updated",
          resource_type: "Article",
          resource_id: key,
          title: key,
          occurred_at: 1.hour.ago,
          detected_at: 1.hour.ago,
          idempotency_key: key
        )
      end
    end
  end
end
