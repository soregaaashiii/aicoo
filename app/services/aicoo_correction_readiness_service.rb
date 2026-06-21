class AicooCorrectionReadinessService
  ACTION_RESULT_REQUIRED = 10
  EVALUATED_REQUIRED = 10
  REVENUE_EVENT_REQUIRED = 20
  BUSINESS_METRIC_DAILY_REQUIRED = 30

  Item = Data.define(:key, :label, :current_count, :required_count, :ready) do
    def shortage_count
      [ required_count.to_i - current_count.to_i, 0 ].max
    end
  end
  BusinessItem = Data.define(:business, :messages, :missing_keys) do
    def ready?
      messages.empty?
    end
  end
  Result = Data.define(:items, :business_items) do
    def item(key)
      items.find { |entry| entry.key == key }
    end
  end

  def call
    Result.new(
      items: overall_items,
      business_items: business_items
    )
  end

  private

  def overall_items
    [
      item(:judge_data, "Judgeデータ不足", ActionResult.evaluated.count, EVALUATED_REQUIRED),
      item(:action_results, "ActionResult不足", ActionResult.count, ACTION_RESULT_REQUIRED),
      item(:evaluated, "evaluated不足", ActionResult.evaluated.count, EVALUATED_REQUIRED),
      item(:revenue, "revenue不足", RevenueEvent.revenue.count, REVENUE_EVENT_REQUIRED),
      item(:business_metric_daily, "BusinessMetricDaily不足", BusinessMetricDaily.count, Business.count * BUSINESS_METRIC_DAILY_REQUIRED)
    ]
  end

  def item(key, label, current_count, required_count)
    Item.new(
      key:,
      label:,
      current_count: current_count.to_i,
      required_count: required_count.to_i,
      ready: current_count.to_i >= required_count.to_i
    )
  end

  def business_items
    Business.includes(:action_results, :revenue_events, :business_metric_dailies).order(:name).map do |business|
      messages = []
      missing_keys = []
      append_message(messages, missing_keys, :action_results, business.action_results.count, ACTION_RESULT_REQUIRED, "#{business.name}: ActionResult")
      append_message(messages, missing_keys, :evaluated, business.action_results.evaluated.count, EVALUATED_REQUIRED, "#{business.name}: evaluated")
      append_message(messages, missing_keys, :revenue, business.revenue_events.revenue.count, 1, "#{business.name}: RevenueEvent")
      append_message(messages, missing_keys, :business_metric_daily, business.business_metric_dailies.count, BUSINESS_METRIC_DAILY_REQUIRED, "#{business.name}: BusinessMetricDaily")

      BusinessItem.new(business:, messages:, missing_keys:)
    end
  end

  def append_message(messages, missing_keys, key, current_count, required_count, label)
    return if current_count >= required_count

    missing_keys << key
    messages << "#{label} #{current_count}/#{required_count}件"
  end
end
