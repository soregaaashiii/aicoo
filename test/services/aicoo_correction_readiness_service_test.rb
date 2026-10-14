require "test_helper"

class AicooCorrectionReadinessServiceTest < ActiveSupport::TestCase
  test "reports overall and business shortages with current and required counts" do
    business = businesses(:suelog)
    business.business_metric_dailies.create!(recorded_on: Date.current, clicks: 1)

    result = AicooCorrectionReadinessService.new.call

    assert_equal "Judgeデータ不足", result.item(:judge_data).label
    assert_operator result.item(:action_results).required_count, :>, result.item(:action_results).current_count
    business_item = result.business_items.find { |item| item.business == business }
    assert_includes business_item.messages.join("\n"), "ActionResult"
    assert_includes business_item.messages.join("\n"), "BusinessMetricDaily"
  end

  test "uses grouped counts without loading every readiness record" do
    instantiated_classes = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      instantiated_classes << payload[:class_name]
    end

    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      AicooCorrectionReadinessService.new.call
    end

    assert_not_includes instantiated_classes, "ActionResult"
    assert_not_includes instantiated_classes, "RevenueEvent"
    assert_not_includes instantiated_classes, "BusinessMetricDaily"
  end

  test "grouped counts preserve the previous totals business values and ordering" do
    result = AicooCorrectionReadinessService.new.call
    businesses = Business.real_businesses.order(:name).to_a

    assert_equal businesses, result.business_items.map(&:business)
    assert_equal ActionResult.count, result.item(:action_results).current_count
    assert_equal ActionResult.evaluated.count, result.item(:evaluated).current_count
    assert_equal RevenueEvent.revenue.count, result.item(:revenue).current_count
    assert_equal BusinessMetricDaily.count, result.item(:business_metric_daily).current_count

    result.business_items.each do |business_item|
      business = business_item.business
      expected_missing_keys = []
      expected_missing_keys << :action_results if business.action_results.count < AicooCorrectionReadinessService::ACTION_RESULT_REQUIRED
      expected_missing_keys << :evaluated if business.action_results.evaluated.count < AicooCorrectionReadinessService::EVALUATED_REQUIRED
      expected_missing_keys << :revenue if business.revenue_events.revenue.count < 1
      expected_missing_keys << :business_metric_daily if business.business_metric_dailies.count < AicooCorrectionReadinessService::BUSINESS_METRIC_DAILY_REQUIRED

      assert_equal expected_missing_keys, business_item.missing_keys, business.name
    end
  end
end
