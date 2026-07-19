require "test_helper"

module Aicoo
  class BusinessActivityLogCreationDiagnosticTest < ActiveSupport::TestCase
    test "reports instrumented creation path and callback chain" do
      activity_log = create_activity("creation-diagnostic-instrumented")
      activity_log.update_columns(
        metadata: {
          "business_activity_log_creation" => {
            "created_by_method" => "ingest",
            "created_by_file" => "app/services/aicoo/activity_ingestor.rb",
            "created_by_line" => 49,
            "persistence_method" => "BusinessActivityLog.record!",
            "active_record_callbacks_enabled" => true
          },
          "activity_evaluation_trigger_chain" => {
            "after_create_called" => true,
            "after_commit_called" => true,
            "trigger_registered" => true,
            "trigger_called" => true,
            "builder_called" => true
          }
        }
      )

      result = BusinessActivityLogCreationDiagnostic.new(business_id: activity_log.business_id).call
      row = result.rows.find { |item| item.event_id == activity_log.id }

      assert_equal "ingest", row.created_by_method
      assert_equal "app/services/aicoo/activity_ingestor.rb", row.created_by_file
      assert_equal 49, row.created_by_line
      assert_equal "BusinessActivityLog.record!", row.persistence_method
      assert_equal true, row.active_record_callbacks_enabled
      assert_equal true, row.after_create_called
      assert_equal true, row.after_commit_called
      assert_nil row.callback_skipped_reason
      assert_equal true, row.trigger_registered
      assert_equal true, row.trigger_called
      assert_equal true, row.builder_called
    end

    test "does not claim callbacks ran for legacy uninstrumented records" do
      activity_log = create_activity("creation-diagnostic-legacy")
      activity_log.update_columns(metadata: {})

      result = BusinessActivityLogCreationDiagnostic.new(business_id: activity_log.business_id).call
      row = result.rows.find { |item| item.event_id == activity_log.id }

      assert_equal "legacy_uninstrumented", row.created_by_method
      assert_equal "unknown", row.persistence_method
      assert_nil row.active_record_callbacks_enabled
      assert_equal false, row.after_create_called
      assert_equal false, row.after_commit_called
      assert_equal "creation_provenance_missing", row.callback_skipped_reason
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
