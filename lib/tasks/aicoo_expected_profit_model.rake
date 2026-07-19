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

      output = [
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
      ]
      if result.improvement_type == "rank_improvement"
        rank = model["rank_improvement_diagnostics"].to_h
        output += [
          "current_impressions=#{rank['current_impressions']}",
          "expected_impressions_after_rank_gain=#{rank['expected_impressions_after_rank_gain']}",
          "impression_gain_rate=#{rank['impression_gain_rate']}",
          "current_ctr=#{rank['current_ctr']}",
          "expected_ctr_after_rank_gain=#{rank['expected_ctr_after_rank_gain']}",
          "click_gain_from_ctr=#{rank['click_gain_from_ctr']}",
          "click_gain_from_impressions=#{rank['click_gain_from_impressions']}",
          "total_expected_click_gain=#{rank['total_expected_click_gain']}"
        ]
      end
      puts output.join(" ")
    rescue StandardError => e
      puts "candidate_id=#{candidate.id} failed=#{e.class} message=#{e.message}"
    end

    by_type = rows.group_by(&:improvement_type)
    learned_count = rows.count { |row| %w[business_learning improvement_type_learning global_learning].include?(row.model_source) }
    initial_count = rows.count { |row| row.model_source == "initial_coefficients" }
    average = rows.any? ? (rows.sum { |row| row.expected_profit_yen.to_d } / rows.size).round.to_i : 0

    puts "summary"
    puts "checked=#{rows.size}"
    puts "business_average_expected_profit=#{average}"
    puts "improvement_type_average=#{by_type.transform_values { |values| (values.sum { |row| row.expected_profit_yen.to_d } / values.size).round.to_i }.inspect}"
    puts "learned_ratio=#{rows.any? ? (learned_count.to_d / rows.size).round(3) : 0}"
    puts "initial_coefficient_ratio=#{rows.any? ? (initial_count.to_d / rows.size).round(3) : 0}"
  end

  desc "Diagnose ActionResult learning usage for ArticleOpportunity expected value model"
  task diagnose_expected_value_learning: :environment do
    scope = ActionCandidate
      .where.not(status: %w[rejected rejected_duplicate rejected_irrelevant superseded archived done])
      .where("metadata ->> 'value_model_name' = ?", Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME)
      .order(updated_at: :desc)

    limit = ENV.fetch("LIMIT", 200).to_i
    rows = []
    coefficient_keys = Aicoo::ArticleOpportunityExpectedProfit::INITIAL_COEFFICIENTS.keys + [ "rank_impression_gain_rate" ]

    scope.limit(limit).find_each do |candidate|
      result = Aicoo::ArticleOpportunityExpectedProfit.call(candidate)
      model = result.metadata.fetch("expected_profit_model")
      sources = model.fetch("input_sources", {})
      learning_counts = model.fetch("learning_sample_counts", {})
      learning_values = model.fetch("learning_coefficients", {})
      coefficients = model.fetch("coefficients", {})
      row = {
        candidate_id: candidate.id,
        business_id: candidate.business_id,
        improvement_type: result.improvement_type,
        model_source: result.model_source,
        learning_source: result.learning_source,
        expected_profit_yen: result.expected_profit_yen,
        business_sample_count: learning_counts["business_learning"].to_i,
        improvement_type_sample_count: learning_counts["improvement_type_learning"].to_i,
        global_sample_count: learning_counts["global_learning"].to_i,
        sources:,
        learning_values:,
        coefficients:
      }
      rows << row

      coefficient_summary = coefficient_keys.map do |key|
        learned = learning_values[key]
        source = sources[key] || "-"
        current = coefficients[key] || "-"
        "#{key}:current=#{current}:initial=#{Aicoo::ArticleOpportunityExpectedProfit::INITIAL_COEFFICIENTS[key] || '-'}:learned=#{learned || '-'}:source=#{source}"
      end.join(" ")

      puts [
        "candidate_id=#{row[:candidate_id]}",
        "business_id=#{row[:business_id]}",
        "improvement_type=#{row[:improvement_type]}",
        "expected_profit_yen=#{row[:expected_profit_yen]}",
        "model_source=#{row[:model_source]}",
        "learning_source=#{row[:learning_source]}",
        "business_sample_count=#{row[:business_sample_count]}",
        "improvement_type_sample_count=#{row[:improvement_type_sample_count]}",
        "global_sample_count=#{row[:global_sample_count]}",
        "coefficients=\"#{coefficient_summary}\""
      ].join(" ")
    rescue StandardError => e
      puts "candidate_id=#{candidate.id} failed=#{e.class} message=#{e.message}"
    end

    checked = rows.size
    business_learning = rows.count { |row| row[:model_source] == "business_learning" }
    improvement_learning = rows.count { |row| row[:model_source] == "improvement_type_learning" }
    global_learning = rows.count { |row| row[:model_source] == "global_learning" }
    initial = rows.count { |row| row[:model_source] == "initial_coefficients" }
    by_type = rows.group_by { |row| row[:improvement_type] }

    puts "summary"
    puts "checked=#{checked}"
    puts "learned_ratio=#{checked.positive? ? ((business_learning + improvement_learning + global_learning).to_d / checked).round(3) : 0}"
    puts "business_learning_ratio=#{checked.positive? ? (business_learning.to_d / checked).round(3) : 0}"
    puts "improvement_learning_ratio=#{checked.positive? ? (improvement_learning.to_d / checked).round(3) : 0}"
    puts "global_learning_ratio=#{checked.positive? ? (global_learning.to_d / checked).round(3) : 0}"
    puts "initial_ratio=#{checked.positive? ? (initial.to_d / checked).round(3) : 0}"
    puts "improvement_type_learning_counts=#{by_type.transform_values { |items| items.sum { |row| row[:improvement_type_sample_count] } }.inspect}"
    puts "business_learning_counts=#{rows.group_by { |row| row[:business_id] }.transform_values { |items| items.sum { |row| row[:business_sample_count] } }.inspect}"
    puts "coefficient_sources=#{coefficient_keys.index_with { |key| rows.group_by { |row| row[:sources][key] || 'unused' }.transform_values(&:size) }.inspect}"
  end
end
