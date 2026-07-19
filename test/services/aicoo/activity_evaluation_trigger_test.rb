require "test_helper"

module Aicoo
  class ActivityEvaluationTriggerTest < ActiveSupport::TestCase
    test "invokes builder for existing activity logs and records trigger metadata" do
      business = businesses(:suelog)
      activity_log = without_automatic_trigger do
        BusinessActivityLog.create!(
          business:,
          source_app: "suelog",
          activity_type: "article_updated",
          resource_type: "Article",
          resource_id: "trigger-article",
          title: "Trigger article",
          occurred_at: 1.hour.ago,
          detected_at: 1.hour.ago,
          idempotency_key: "trigger-article-updated"
        )
      end

      result = ActivityEvaluationTrigger.call(
        business:,
        invoked_by: "Manual",
        trigger_event_id: activity_log.id
      )

      assert_operator result.builder_invoked_count, :>=, 1
      assert_operator result.builder_completed_count, :>=, 1
      assert_equal 0, result.builder_failed_count
      assert_equal 3, activity_log.activity_evaluations.count
      trigger = activity_log.reload.metadata.fetch("activity_evaluation_trigger")
      assert_equal true, trigger["builder_invoked"]
      assert_equal true, trigger["builder_completed"]
      assert_equal "Manual", trigger["invoked_by"]
      assert_equal activity_log.id, trigger["trigger_event_id"]
      chain = activity_log.metadata.fetch("activity_evaluation_trigger_chain")
      assert_equal true, chain["trigger_registered"]
      assert_equal true, chain["trigger_called"]
      assert_equal true, chain["builder_called"]
      assert_equal true, chain["builder_completed"]
    end

    test "one new recorded activity triggers backfill for existing activity logs" do
      business = businesses(:suelog)
      old_log = without_automatic_trigger do
        BusinessActivityLog.create!(
          business:,
          source_app: "suelog",
          activity_type: "article_updated",
          resource_type: "Article",
          resource_id: "old-trigger-article",
          title: "Old trigger article",
          occurred_at: 1.hour.ago,
          detected_at: 1.hour.ago,
          idempotency_key: "old-trigger-article-updated"
        )
      end

      BusinessActivityLog.record!(
        business:,
        attributes: {
          source_app: "suelog",
          activity_type: "article_updated",
          resource_type: "Article",
          resource_id: "new-trigger-article",
          title: "New trigger article",
          idempotency_key: "new-trigger-article-updated"
        }
      )

      assert_equal 3, old_log.activity_evaluations.count
      assert_equal "after_create_commit", old_log.reload.metadata.dig("activity_evaluation_trigger", "invoked_by")
    end

    private

    def without_automatic_trigger(&block)
      ActivityEvaluationTrigger.stub(:call, nil, &block)
    end
  end
end
