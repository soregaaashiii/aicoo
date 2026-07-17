namespace :aicoo do
  desc "Diagnose Business expected value. Usage: BUSINESS_ID=2 bin/rails aicoo:diagnose_business_expected_value"
  task diagnose_business_expected_value: :environment do
    business = if ENV["BUSINESS_ID"].present?
      Business.find(ENV.fetch("BUSINESS_ID"))
    elsif ENV["BUSINESS_NAME"].present?
      Business.find_by!(name: ENV.fetch("BUSINESS_NAME"))
    else
      Business.real_businesses.order(:id).first
    end

    result = Aicoo::BusinessExpectedValue.call(business)
    puts "business_id=#{business.id}"
    puts "business_name=#{business.name}"
    puts "business_state=#{business.metadata.to_h.dig('business_value_model', 'business_state') || (result.new_business_value ? 'new_business' : 'existing')}"
    puts "model_name=#{business.metadata.to_h.dig('business_value_model', 'model_name') || result.calculation_method}"
    puts "base_business_value_yen=#{result.base_business_value_yen}"
    puts "action_opportunity_value_yen=#{result.action_opportunity_value_yen}"
    puts "candidate_raw_sum=#{result.raw_candidate_sum_yen}"
    puts "unique_opportunity_count=#{result.unique_opportunity_count}"
    puts "duplicate_candidate_count=#{result.duplicate_candidate_count}"
    puts "duplicate_adjustment_yen=#{result.duplicate_adjustment_yen}"
    puts "market_limit_adjustment_yen=#{result.market_limit_adjustment_yen}"
    puts "cannibalization_adjustment_yen=#{result.cannibalization_adjustment_yen}"
    puts "confidence_adjustment_yen=#{result.confidence_adjustment_yen}"
    puts "cost_yen=#{result.cost_yen}"
    puts "final_expected_value_yen=#{result.expected_total_value_yen}"
    puts "calculation_method=#{result.calculation_method}"
    puts "confidence=#{result.confidence}"
    if result.base_business_value
      base = result.base_business_value
      puts "base_value_source=#{base.source}"
      puts "business_metric_period=#{base.observed_period_start}..#{base.observed_period_end} days=#{base.observed_days}"
      puts "business_metric_profit_yen=#{base.business_metric_inputs['measured_profit_yen']}"
      puts "shop_click_counts=#{base.shop_click_inputs.inspect}"
      puts "gsc_clicks=#{base.gsc_inputs['clicks']}"
      puts "gsc_impressions=#{base.gsc_inputs['impressions']}"
      puts "ga4_pageviews=#{base.ga4_inputs['pageviews']}"
      puts "ga4_active_users=#{base.ga4_inputs['active_users']}"
      puts "proxy_weight_inputs=#{base.proxy_weight_inputs.inspect}"
      puts "double_count_prevention=#{base.double_count_prevention}"
      puts "active_candidate_count=#{business.action_candidates.active_for_ranking.count}"
    end

    if result.new_business_value
      value = result.new_business_value
      puts ""
      puts "New Business:"
      puts "estimated_90d_profit=#{value.estimated_90d_profit_yen}"
      puts "success_probability=#{value.validation_success_probability}"
      puts "validation_cost=#{value.validation_cost_yen}"
      puts "final_expected_value=#{value.final_expected_value_yen}"
      puts "missing_inputs=#{value.missing_inputs.join(",")}"
    else
      puts ""
      puts "Opportunities:"
      result.opportunities.each do |row|
        puts "- key=#{row.key}"
        puts "  raw_sum=#{row.raw_sum_yen}"
        puts "  impressions=#{row.input_values['impressions']}"
        puts "  available_clicks=#{row.input_values['available_clicks']}"
        puts "  conversion_rate=#{row.input_values['conversion_rate']}"
        puts "  profit_per_conversion=#{row.input_values['profit_per_conversion']}"
        puts "  success_probability=#{row.input_values['success_probability']}"
        puts "  market_limit=#{row.market_limit_yen || 'none'}"
        puts "  final_value=#{row.final_value_yen}"
        puts "  duplicate_candidates=#{row.duplicate_candidate_count}"
        puts "  duplicate_adjustment=#{row.duplicate_adjustment_yen}"
        puts "  market_limit_adjustment=#{row.market_limit_adjustment_yen}"
        puts "  cannibalization_adjustment=#{row.cannibalization_adjustment_yen}"
        puts "  confidence_adjustment=#{row.confidence_adjustment_yen}"
        puts "  cost=#{row.cost_yen}"
        puts "  anomaly_detected=#{row.anomaly_detected}"
        puts "  anomaly_reason=#{row.anomaly_reason}"
        puts "  candidate_ids=#{row.candidate_ids.join(",")}"
      end
    end
  end
end
