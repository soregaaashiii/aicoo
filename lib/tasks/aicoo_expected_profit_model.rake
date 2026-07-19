namespace :aicoo do
  desc "Diagnose grounded expected profit model for ArticleOpportunity candidates"
  task diagnose_expected_profit_model: :environment do
    scope = ActionCandidate
      .where.not(status: %w[rejected rejected_duplicate rejected_irrelevant superseded archived done])
      .where("metadata ->> 'value_model_name' = ?", Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME)
      .order(updated_at: :desc)

    limit = ENV.fetch("LIMIT", 100).to_i
    rows = []

    scope.limit(limit).find_each do |candidate|
      result = Aicoo::ArticleOpportunityExpectedProfit.call(candidate)
      model = result.metadata.fetch("expected_profit_model")
      rows << result

      puts [
        "candidate_id=#{candidate.id}",
        "improvement_type=#{result.improvement_type}",
        "expected_profit=#{result.expected_profit_yen}",
        "expected_improvement=#{candidate.metadata.to_h['expected_improvement_score']}",
        "expected_ctr_gain=#{result.expected_ctr_gain}",
        "expected_click_gain=#{result.expected_click_gain}",
        "expected_conversion_gain=#{result.expected_conversion_gain}",
        "expected_revenue=#{result.expected_revenue_yen}",
        "success_probability=#{result.success_probability}",
        "work_cost=#{result.work_cost_yen}",
        "confidence=#{result.confidence}",
        "model_source=#{result.model_source}",
        "learning_source=#{result.learning_source}",
        "calibration_version=#{result.calibration_version}",
        "assumed_fields=#{Array(model['assumed_fields']).join(',')}"
      ].join(" ")
    rescue StandardError => e
      puts "candidate_id=#{candidate.id} failed=#{e.class} message=#{e.message}"
    end

    by_type = rows.group_by(&:improvement_type)
    learned_count = rows.count { |row| %w[business_learning improvement_type_learning].include?(row.model_source) }
    initial_count = rows.count { |row| row.model_source == "initial_coefficients" }
    average = rows.any? ? (rows.sum { |row| row.expected_profit_yen.to_d } / rows.size).round.to_i : 0

    puts "summary"
    puts "checked=#{rows.size}"
    puts "business_average_expected_profit=#{average}"
    puts "improvement_type_average=#{by_type.transform_values { |values| (values.sum { |row| row.expected_profit_yen.to_d } / values.size).round.to_i }.inspect}"
    puts "learned_ratio=#{rows.any? ? (learned_count.to_d / rows.size).round(3) : 0}"
    puts "initial_coefficient_ratio=#{rows.any? ? (initial_count.to_d / rows.size).round(3) : 0}"
  end
end
