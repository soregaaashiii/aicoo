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
    max_value = values.max || 0.to_d

    return business_chart_ratio_max(max_value) if metric.to_s == "ctr"

    [ max_value, 1.to_d ].max
  end

  def business_chart_height(point, metric, max_value)
    value = business_chart_decimal(point.values[metric])
    return 4 if value.zero?

    [ (value / business_chart_decimal(max_value) * 100).round, 8 ].max
  end

  def business_chart_value_label(value, metric: nil)
    return "データ不足" if value.nil?

    number = value.to_d
    return business_chart_percentage_label(number) if metric.to_s == "ctr"

    formatted = if number.frac.zero?
      number.to_i.to_s
    elsif number.abs >= 1
      number.round(2).to_s("F")
    else
      number.round(4).to_s("F")
    end

    formatted = formatted.sub(/0+\z/, "").sub(/\.\z/, "") if formatted.include?(".")
    number_with_delimiter(formatted)
  end

  private

  def business_chart_ratio_max(max_value)
    return 0.01.to_d if max_value.zero?

    max_value * 1.1.to_d
  end

  def business_chart_percentage_label(number)
    percentage = number * 100
    precision = if percentage.zero?
      0
    elsif percentage.abs >= 10
      1
    elsif percentage.abs >= 1
      2
    else
      3
    end

    number_to_percentage(percentage, precision:, strip_insignificant_zeros: true)
  end

  def business_chart_decimal(value)
    value.nil? ? 0.to_d : value.to_d
  end
end
