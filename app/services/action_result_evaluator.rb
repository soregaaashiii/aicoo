class ActionResultEvaluator
  def self.evaluate_pending!
    results = ActionResult.where(evaluation_status: "pending").where(evaluated_on: ..Date.current).find_each.map do |action_result|
      new(action_result, refresh_learning: false).call
    end
    Aicoo::ExpectedValueLearningRefresh.refresh_after_action_result!(results.find { |result| result.evaluation_status == "evaluated" }, source: "action_result_evaluator") if results.any? { |result| result.evaluation_status == "evaluated" }
    results
  end

  def initialize(action_result, refresh_learning: true)
    @action_result = action_result
    @business = action_result.business
    @refresh_learning = refresh_learning
  end

  def call
    return skip!("実行前後7日分のBusinessMetricDailyが不足しています") unless enough_metric_data?

    action_result.assign_attributes(metric_delta_attributes)
    action_result.assign_attributes(revenue_attributes)
    action_result.evaluation_status = "evaluated"
    action_result.note = [ action_result.note.presence, "ActionResultEvaluatorで評価しました" ].compact.join("\n")
    action_result.save!
    Aicoo::ExpectedValueLearningRefresh.refresh_after_action_result!(action_result, source: "action_result_evaluator") if refresh_learning
    action_result
  end

  private

  attr_reader :action_result, :business, :refresh_learning

  def enough_metric_data?
    before_metrics.any? && after_metrics.any?
  end

  def metric_delta_attributes
    attributes = {
      actual_proxy_score_delta: average_proxy_score(after_metrics) - average_proxy_score(before_metrics)
    }

    ActionResult::DELTA_METRICS.each do |metric|
      attributes[:"actual_#{metric}_delta"] = (average_metric(after_metrics, metric) - average_metric(before_metrics, metric)).round
    end

    attributes
  end

  def revenue_attributes
    revenue = business.revenue_events.revenue.where(occurred_on: result_period).sum(:amount)
    expense = business.revenue_events.expense.where(occurred_on: result_period).sum(:amount)

    {
      actual_revenue_yen: revenue,
      actual_profit_yen: revenue - expense
    }
  end

  def skip!(reason)
    action_result.update!(
      evaluation_status: "skipped",
      note: [ action_result.note.presence, reason ].compact.join("\n")
    )
    action_result
  end

  def before_metrics
    @before_metrics ||= business.business_metric_dailies.where(recorded_on: before_range).to_a
  end

  def after_metrics
    @after_metrics ||= business.business_metric_dailies.where(recorded_on: after_range).to_a
  end

  def before_range
    (action_result.executed_on - 7)...action_result.executed_on
  end

  def after_range
    (action_result.executed_on + 1)..[ action_result.executed_on + 7, action_result.evaluated_on ].min
  end

  def result_period
    action_result.executed_on..action_result.evaluated_on
  end

  def average_proxy_score(records)
    return 0.to_d if records.empty?

    records.sum(&:proxy_score).to_d / records.size
  end

  def average_metric(records, metric)
    return 0.to_d if records.empty?

    records.sum { |record| record.public_send(metric).to_i }.to_d / records.size
  end
end
