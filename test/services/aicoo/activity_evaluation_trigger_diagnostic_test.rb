require "test_helper"

module Aicoo
  class ActivityEvaluationTriggerDiagnosticTest < ActiveSupport::TestCase
    test "reports invoked and not invoked activity logs" do
      business = businesses(:suelog)
      invoked_log = create_activity(business, "trigger-diagnostic-invoked")
      missing_log = create_activity(business, "trigger-diagnostic-missing")
      ActivityEvaluation.create!(
        business:,
        business_activity_log: invoked_log,
        evaluation_window_days: 7,
        status: "pending"
      )

      result = ActivityEvaluationTriggerDiagnostic.new(business_id: business.id).call
      invoked_row = result.rows.find { |row| row.event_id == invoked_log.id }
      missing_row = result.rows.find { |row| row.event_id == missing_log.id }

      assert_equal true, invoked_row.builder_invoked
      assert_equal "legacy_builder", invoked_row.invoked_by
      assert_equal false, missing_row.builder_invoked
      assert_equal "activity_evaluation_builder_not_invoked", missing_row.skip_reason
      assert_operator result.summary.builder_not_invoked_count, :>=, 1
      assert_operator result.summary.reason_counts["activity_evaluation_builder_not_invoked"], :>=, 1
    end

    private

    def create_activity(business, key)
      BusinessActivityLog.create!(
        business:,
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
