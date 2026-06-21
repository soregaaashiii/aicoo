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
end
