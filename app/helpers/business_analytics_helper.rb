module BusinessAnalyticsHelper
  def business_analytics_value(value, currency: false, percentage: false, precision: 0)
    return "データ不足" if value.nil?

    if percentage
      number_to_percentage(value.to_d * 100, precision: 1)
    elsif currency
      number_to_currency(value.to_i, unit: "¥", precision:)
    else
      number_with_delimiter(value)
    end
  end

  def business_chart_max(series, metric)
    values = series.map { |point| business_chart_decimal(point.values[metric]) }
    [ values.max || 0.to_d, 1.to_d ].max
  end

  def business_chart_height(point, metric, max_value)
    value = business_chart_decimal(point.values[metric])
    return 4 if value.zero?

    [ (value / business_chart_decimal(max_value) * 100).round, 8 ].max
  end

  private

  def business_chart_decimal(value)
    value.nil? ? 0.to_d : value.to_d
  end
end
