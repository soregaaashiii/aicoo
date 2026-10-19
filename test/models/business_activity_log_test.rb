require "test_helper"

class BusinessActivityLogTest < ActiveSupport::TestCase
  test "creates activity log with idempotency per business" do
    business = businesses(:suelog)
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
    chain = log.reload.metadata.fetch("activity_evaluation_trigger_chain")
    assert_equal true, chain["after_commit_skipped"]
    assert_equal false, chain["trigger_called"]
    assert_equal "daily_run_deferred", chain["skip_reason"]
    assert Aicoo::ActivityEvaluationBuilder.evaluation_scope.where(id: log.id).exists?
    creation = log.metadata.fetch("business_activity_log_creation")
    assert_equal "BusinessActivityLog.record!", creation["persistence_method"]
    assert_includes creation["created_by_method"], "BusinessActivityLogTest"
    assert_equal "test/models/business_activity_log_test.rb", creation["created_by_file"]
    assert_equal true, creation["active_record_callbacks_enabled"]
  end

  test "direct association creation defers evaluation to daily run" do
    business = businesses(:suelog)
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

    chain = activity_log.reload.metadata.fetch("activity_evaluation_trigger_chain")
    assert_equal true, chain["after_create_called"]
    assert_equal true, chain["after_commit_called"]
    assert_equal true, chain["after_commit_skipped"]
    assert_equal true, chain["trigger_registered"]
    assert_equal false, chain["trigger_called"]
    assert_equal false, chain["trigger_completed"]
    assert_equal "daily_run_deferred", chain["return_point"]
    assert_equal "daily_run_deferred", chain["skip_reason"]
    assert Aicoo::ActivityEvaluationBuilder.evaluation_scope.where(id: activity_log.id).exists?
    creation = activity_log.metadata.fetch("business_activity_log_creation")
    assert_equal "ActiveRecord#create", creation["persistence_method"]
    assert_equal true, creation["active_record_callbacks_enabled"]
  end
end
