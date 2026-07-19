require "test_helper"

class BusinessActivityLogTest < ActiveSupport::TestCase
  test "creates activity log with idempotency per business" do
    business = businesses(:suelog)
    trigger_calls = []

    Aicoo::ActivityEvaluationTrigger.stub(:call, ->(**args) { trigger_calls << args; successful_trigger_result }) do
      log = BusinessActivityLog.record!(
        business:,
        attributes: {
          source_app: "suelog",
          activity_type: "shop_created",
          resource_type: "Shop",
          resource_id: "1",
          title: "Shop作成",
          idempotency_key: "shop-1-created"
        }
      )
      duplicate = BusinessActivityLog.record!(
        business:,
        attributes: {
          source_app: "suelog",
          activity_type: "shop_created",
          resource_type: "Shop",
          resource_id: "1",
          title: "Shop作成 duplicate",
          idempotency_key: "shop-1-created"
        }
      )

      assert_equal log, duplicate
      assert_equal "Shop作成", duplicate.title
      assert_equal "pending", log.evaluation_status
      assert_equal 1, trigger_calls.size
      assert_equal "after_create_commit", trigger_calls.first[:invoked_by]
      assert_equal log.id, trigger_calls.first[:trigger_event_id]
      creation = log.reload.metadata.fetch("business_activity_log_creation")
      assert_equal "BusinessActivityLog.record!", creation["persistence_method"]
      assert_includes creation["created_by_method"], "BusinessActivityLogTest"
      assert_equal "test/models/business_activity_log_test.rb", creation["created_by_file"]
      assert_equal true, creation["active_record_callbacks_enabled"]
    end
  end

  test "direct association creation invokes trigger after commit" do
    business = businesses(:suelog)
    trigger_calls = []

    Aicoo::ActivityEvaluationTrigger.stub(:call, ->(**args) { trigger_calls << args; successful_trigger_result }) do
      activity_log = business.business_activity_logs.create!(
        source_app: "aicoo",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "direct-create",
        title: "Direct create",
        occurred_at: Time.current,
        detected_at: Time.current,
        idempotency_key: "direct-create-trigger"
      )

      assert_equal 1, trigger_calls.size
      assert_equal "after_create_commit", trigger_calls.first[:invoked_by]
      assert_equal activity_log.id, trigger_calls.first[:trigger_event_id]
      chain = activity_log.reload.metadata.fetch("activity_evaluation_trigger_chain")
      assert_equal true, chain["after_create_called"]
      assert_equal true, chain["after_commit_called"]
      assert_equal true, chain["trigger_registered"]
      assert_equal true, chain["trigger_called"]
      assert_equal true, chain["trigger_completed"]
      assert_equal true, chain["builder_called"]
      assert_equal true, chain["builder_completed"]
      creation = activity_log.metadata.fetch("business_activity_log_creation")
      assert_equal "ActiveRecord#create", creation["persistence_method"]
      assert_equal "test/models/business_activity_log_test.rb", creation["created_by_file"]
      assert_equal true, creation["active_record_callbacks_enabled"]
    end
  end

  private

  def successful_trigger_result
    Aicoo::ActivityEvaluationTrigger::Result.new(
      builder_should_run_count: 1,
      builder_invoked_count: 1,
      builder_completed_count: 1,
      builder_failed_count: 0,
      builder_result: nil,
      exception: nil
    )
  end
end
