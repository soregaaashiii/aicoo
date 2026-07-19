require "test_helper"

module Aicoo
  class ActivityEvaluationBuilderDiagnosticTest < ActiveSupport::TestCase
    test "reports generated and missing evaluations for every activity" do
      business = businesses(:suelog)
      generated_log = create_activity(business, "diagnostic-generated")
      missing_log = create_activity(business, "diagnostic-missing")
      ActivityEvaluation.create!(
        business:,
        business_activity_log: generated_log,
        evaluation_window_days: 7,
        status: "pending"
      )

      result = ActivityEvaluationBuilderDiagnostic.new(business_id: business.id).call
      generated_row = result.rows.find { |row| row.event_id == generated_log.id }
      missing_row = result.rows.find { |row| row.event_id == missing_log.id }

      assert_equal true, generated_row.evaluation_generated
      assert_equal "evaluation_windows_missing", generated_row.missing_reason
      assert_equal false, missing_row.evaluation_generated
      assert_equal "activity_evaluation_builder_not_run", missing_row.missing_reason
      assert_operator result.summary.generation_failed_count, :>=, 1
      assert_operator result.summary.reason_counts["activity_evaluation_builder_not_run"], :>=, 1
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
