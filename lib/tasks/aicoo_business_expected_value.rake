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
    puts "raw_candidate_sum=#{result.raw_candidate_sum_yen}"
    puts "unique_opportunity_count=#{result.unique_opportunity_count}"
    puts "duplicate_candidate_count=#{result.duplicate_candidate_count}"
    puts "duplicate_adjustment_yen=#{result.duplicate_adjustment_yen}"
    puts "cap_adjustment_yen=#{result.cap_adjustment_yen}"
    puts "confidence_adjustment_yen=#{result.confidence_adjustment_yen}"
    puts "cost_yen=#{result.cost_yen}"
    puts "final_expected_value_yen=#{result.expected_total_value_yen}"
    puts "calculation_method=#{result.calculation_method}"
    puts "confidence=#{result.confidence}"

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
        puts "  cap=#{row.cap_yen}"
        puts "  final_value=#{row.final_value_yen}"
        puts "  duplicate_candidates=#{row.duplicate_candidate_count}"
        puts "  duplicate_adjustment=#{row.duplicate_adjustment_yen}"
        puts "  cap_adjustment=#{row.cap_adjustment_yen}"
        puts "  confidence_adjustment=#{row.confidence_adjustment_yen}"
        puts "  cost=#{row.cost_yen}"
        puts "  candidate_ids=#{row.candidate_ids.join(",")}"
      end
    end
  end
end
