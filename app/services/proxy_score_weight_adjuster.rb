class ProxyScoreWeightAdjuster
  BASE_ADJUSTMENT_RATE = 0.01.to_d
  GLOBAL_RATE_MULTIPLIER = 0.5.to_d
  SHALLOW_WEIGHT_COLUMNS = %i[impressions_weight pageviews_weight sessions_weight].freeze
  CLICK_WEIGHT_COLUMNS = %i[clicks_weight].freeze
  REVENUE_NEAR_WEIGHT_COLUMNS = %i[phone_clicks_weight map_clicks_weight affiliate_clicks_weight].freeze

  def adjust_all_businesses!(start_date:, end_date:)
    Business.find_each.map do |business|
      adjust_business!(business:, start_date:, end_date:)
    end
  end

  def adjust_business!(business:, start_date:, end_date:)
    start_date = start_date.to_date
    end_date = end_date.to_date
    weight = ProxyScoreWeight.build_for_business!(business)
    sample_days_count = business.business_metric_dailies.distinct.count(:recorded_on)
    revenue_events_count = business.revenue_events.revenue.count
    confidence_score = confidence_score(sample_days_count:, revenue_events_count:)
    rate = effective_rate(confidence_score)
    before_weights = weight.weights_hash

    if business_adjustment_blocked?(sample_days_count, revenue_events_count)
      return log_adjustment(
        weight:,
        business:,
        start_date:,
        end_date:,
        before_weights:,
        after_weights: before_weights,
        confidence_score:,
        sample_days_count:,
        revenue_events_count:,
        adjustment_rate: 0,
        reason: "sample size too small"
      )
    end

    reason = apply_business_adjustment!(weight, business, start_date, end_date, rate)
    weight.update!(confidence_score:, adjusted_at: Time.current, note: reason)
    log_adjustment(
      weight:,
      business:,
      start_date:,
      end_date:,
      before_weights:,
      after_weights: weight.weights_hash,
      confidence_score:,
      sample_days_count:,
      revenue_events_count:,
      adjustment_rate: rate,
      reason:
    )
  end

  def adjust_global!(start_date:, end_date:)
    start_date = start_date.to_date
    end_date = end_date.to_date
    weight = ProxyScoreWeight.build_global!
    sample_days_count = BusinessMetricDaily.count
    revenue_events_count = RevenueEvent.revenue.count
    confidence_score = confidence_score(sample_days_count:, revenue_events_count:)
    rate = effective_rate(confidence_score) * GLOBAL_RATE_MULTIPLIER
    before_weights = weight.weights_hash

    unless global_adjustable?(sample_days_count, revenue_events_count)
      return log_adjustment(
        weight:,
        business: nil,
        start_date:,
        end_date:,
        before_weights:,
        after_weights: before_weights,
        confidence_score:,
        sample_days_count:,
        revenue_events_count:,
        adjustment_rate: 0,
        reason: "skipped global adjustment due to insufficient revenue events or metric days"
      )
    end

    reason = apply_global_adjustment!(weight, start_date, end_date, rate)
    weight.update!(confidence_score:, adjusted_at: Time.current, note: reason)
    log_adjustment(
      weight:,
      business: nil,
      start_date:,
      end_date:,
      before_weights:,
      after_weights: weight.weights_hash,
      confidence_score:,
      sample_days_count:,
      revenue_events_count:,
      adjustment_rate: rate,
      reason:
    )
  end

  private

  def business_adjustment_blocked?(sample_days_count, revenue_events_count)
    sample_days_count < 30 && revenue_events_count < 10
  end

  def global_adjustable?(sample_days_count, revenue_events_count)
    sample_days_count >= 90 && revenue_events_count >= 20
  end

  def confidence_score(sample_days_count:, revenue_events_count:)
    base_score =
      case sample_days_count
      when 0...30 then [ (sample_days_count / 3.0).floor, 10 ].min
      when 30...90 then 20
      when 90...180 then 50
      when 180...365 then 70
      else 90
      end

    [ base_score + [ revenue_events_count, 10 ].min, 100 ].min
  end

  def effective_rate(confidence_score)
    BASE_ADJUSTMENT_RATE * (confidence_score.to_d / 100)
  end

  def apply_business_adjustment!(weight, business, start_date, end_date, rate)
    period_revenues = business.revenue_events.revenue.where(occurred_on: start_date..end_date)
    if period_revenues.exists?
      increased_columns = increase_revenue_followed_metrics!(weight, business, period_revenues, rate)
      return "adjusted because revenue followed proxy growth: #{increased_columns.join(', ')}" if increased_columns.any?

      "revenue exists but no proxy growth was found"
    else
      reduce_shallow_metrics_without_revenue!(weight, business, start_date, end_date, rate)
    end
  end

  def apply_global_adjustment!(weight, start_date, end_date, rate)
    period_revenues = RevenueEvent.revenue.where(occurred_on: start_date..end_date).includes(:business)
    if period_revenues.exists?
      increased_columns = period_revenues.flat_map do |revenue_event|
        increase_from_metric_scope!(weight, revenue_event.business.business_metric_dailies, revenue_event.occurred_on, rate)
      end.uniq
      return "adjusted global because revenue followed proxy growth: #{increased_columns.join(', ')}" if increased_columns.any?

      "global revenue exists but no proxy growth was found"
    elsif BusinessMetricDaily.where(recorded_on: start_date..end_date).exists?
      reduce_columns!(weight, SHALLOW_WEIGHT_COLUMNS, rate)
      reduce_columns!(weight, CLICK_WEIGHT_COLUMNS, rate / 2)
      "reduced global shallow metrics because proxy grew without revenue"
    else
      "no proxy growth or revenue in period"
    end
  end

  def increase_revenue_followed_metrics!(weight, business, period_revenues, rate)
    period_revenues.flat_map do |revenue_event|
      increase_from_metric_scope!(weight, business.business_metric_dailies, revenue_event.occurred_on, rate)
    end.uniq
  end

  def increase_from_metric_scope!(weight, metric_scope, revenue_date, rate)
    metrics = metric_scope.where(recorded_on: (revenue_date - 7)...revenue_date)
    positive_columns = ProxyScoreWeight::METRIC_TO_WEIGHT.filter_map do |metric, column|
      column if metrics.sum(metric).positive?
    end

    increase_columns!(weight, positive_columns, rate)
    positive_columns
  end

  def reduce_shallow_metrics_without_revenue!(weight, business, start_date, end_date, rate)
    metrics = business.business_metric_dailies.where(recorded_on: start_date..end_date)
    return "no proxy growth or revenue in period" unless metrics.sum { |metric| metric.proxy_score }.positive?

    reduce_columns!(weight, SHALLOW_WEIGHT_COLUMNS, rate)
    reduce_columns!(weight, CLICK_WEIGHT_COLUMNS, rate / 2)
    "reduced shallow metrics because proxy grew without revenue"
  end

  def increase_columns!(weight, columns, rate)
    columns.each { |column| adjust_column!(weight, column, rate) }
  end

  def reduce_columns!(weight, columns, rate)
    columns.each { |column| adjust_column!(weight, column, -rate) }
  end

  def adjust_column!(weight, column, rate)
    value = weight.public_send(column).to_d
    weight.public_send("#{column}=", value * (1.to_d + rate))
    weight.clamp_weights
  end

  def log_adjustment(weight:, business:, start_date:, end_date:, before_weights:, after_weights:, confidence_score:,
                     sample_days_count:, revenue_events_count:, adjustment_rate:, reason:)
    weight.proxy_score_weight_adjustment_logs.create!(
      business:,
      start_date:,
      end_date:,
      before_weights: stringify_weights(before_weights),
      after_weights: stringify_weights(after_weights),
      confidence_score:,
      sample_days_count:,
      revenue_events_count:,
      adjustment_rate:,
      reason:,
      adjusted_at: Time.current
    )
  end

  def stringify_weights(weights)
    weights.transform_values { |value| value.to_d.to_s }
  end
end
