namespace :aicoo do
  desc "Diagnose Today ranking expected yen values and non-yen ranking usage"
  task diagnose_today_expected_value_ranking: :environment do
    format_value = lambda do |value|
      case value
      when BigDecimal
        value.to_f.round(4)
      when Float
        value.round(4)
      else
        value.presence || "-"
      end
    end

    per_page = ENV.fetch("LIMIT", "500").to_i
    board = Aicoo::TodayActionBoard.new(mode: "revenue", per_page:)
    raw_items = board.send(:candidate_items)
    today_items = board.send(:select_today_items, raw_items)
    diagnostics_by_mode = Aicoo::TodayActionBoard::MODES.index_with do |mode|
      Aicoo::ActionExpectedValueRanking.new(items: today_items, mode:, per_page:).diagnostic_rows
    end
    ranks_by_mode = Aicoo::TodayActionBoard::MODES.index_with do |mode|
      Aicoo::ActionExpectedValueRanking.new(items: today_items, mode:, per_page:).call.items.each_with_object({}) do |item, hash|
        hash[item.stable_id] = item.rank
      end
    end

    rows = diagnostics_by_mode.fetch("revenue").map.with_index(1) do |diagnostic, index|
      item = diagnostic.item
      record = item.record if item.respond_to?(:record)
      classification = diagnostic.classification
      {
        candidate_id: record.is_a?(ActionCandidate) ? record.id : nil,
        candidate_type: item.source_type,
        business_id: classification.business_id,
        current_rank: ranks_by_mode.dig("revenue", item.stable_id) || index,
        total_expected_value_yen: diagnostic.total_expected_value_yen,
        revenue_expected_value_yen: diagnostic.revenue_expected_value_yen,
        traffic_expected_value_yen: diagnostic.traffic_expected_value_yen,
        conversion_expected_value_yen: diagnostic.conversion_expected_value_yen,
        learning_expected_value_yen: diagnostic.learning_expected_value_yen,
        future_expected_value_yen: diagnostic.future_expected_value_yen,
        strategic_expected_value_yen: diagnostic.strategic_expected_value_yen,
        execution_cost_yen: diagnostic.execution_cost_yen,
        risk_cost_yen: diagnostic.risk_cost_yen,
        opportunity_cost_yen: diagnostic.opportunity_cost_yen,
        confidence: item.confidence,
        model_source: record.is_a?(ActionCandidate) ? record.metadata.to_h.dig("expected_profit_model", "model_source") : item.calculation_method,
        ranking_source: diagnostic.ranking_source,
        expected_improvement: diagnostic.expected_improvement,
        non_yen_metric_used_for_ranking: diagnostic.non_yen_metric_used_for_ranking,
        final_rank_revenue: ranks_by_mode.dig("revenue", item.stable_id),
        final_rank_learning: ranks_by_mode.dig("learning", item.stable_id),
        final_rank_balanced: ranks_by_mode.dig("balanced", item.stable_id)
      }
    end

    rows.each do |row|
      puts row.map { |key, value| "#{key}=#{format_value.call(value)}" }.join(" ")
    end

    non_yen_count = rows.count { |row| row[:non_yen_metric_used_for_ranking] }
    expected_improvement_direct_count = rows.count { |row| row[:ranking_source].to_s == "expected_improvement_score" }
    missing_total_count = rows.count { |row| row[:total_expected_value_yen].nil? }
    learned_count = rows.count { |row| row[:model_source].to_s.in?(%w[business_learning improvement_type_learning]) }
    initial_count = rows.count { |row| row[:model_source].to_s == "initial_coefficients" }

    summary = {
      checked: rows.size,
      ranked_by_total_expected_value_yen_count: rows.size - missing_total_count - non_yen_count,
      ranked_by_non_yen_metric_count: non_yen_count,
      expected_improvement_direct_ranking_count: expected_improvement_direct_count,
      missing_total_expected_value_yen_count: missing_total_count,
      initial_coefficient_ratio: rows.any? ? (initial_count.to_d / rows.size).round(3) : 0,
      learned_ratio: rows.any? ? (learned_count.to_d / rows.size).round(3) : 0,
      negative_expected_value_count: rows.count { |row| row[:total_expected_value_yen].to_d.negative? },
      positive_expected_value_count: rows.count { |row| row[:total_expected_value_yen].to_d.positive? }
    }

    puts "summary #{summary.map { |key, value| "#{key}=#{value}" }.join(' ')}"
  end

  desc "Diagnose Today action ranking classification and normalized scores"
  task diagnose_today_ranking: :environment do
    format_value = lambda do |value|
      case value
      when BigDecimal
        value.to_f.round(4)
      when Float
        value.round(4)
      else
        value.presence || "-"
      end
    end

    per_page = ENV.fetch("LIMIT", "500").to_i
    board = Aicoo::TodayActionBoard.new(mode: "revenue", per_page:)
    raw_items = board.send(:candidate_items)
    today_items = board.send(:select_today_items, raw_items)

    diagnostics_by_mode = Aicoo::TodayActionBoard::MODES.index_with do |mode|
      Aicoo::ActionExpectedValueRanking.new(items: today_items, mode:, per_page:).diagnostic_rows
    end
    ranks_by_mode = Aicoo::TodayActionBoard::MODES.index_with do |mode|
      Aicoo::ActionExpectedValueRanking.new(items: today_items, mode:, per_page:).call.items.each_with_object({}) do |item, hash|
        hash[item.stable_id] = item.rank
      end
    end

    rows = diagnostics_by_mode.fetch("revenue").map do |diagnostic|
      item = diagnostic.item
      record = item.record if item.respond_to?(:record)
      classification = diagnostic.classification
      {
        candidate_id: record.is_a?(ActionCandidate) ? record.id : nil,
        business_id: classification.business_id,
        business_name: classification.business_name,
        generation_source: record.respond_to?(:generation_source) ? record.generation_source : item.source_type,
        status: record.respond_to?(:status) ? record.status : nil,
        candidate_category: classification.candidate_category,
        target: classification.target,
        target_valid: classification.target_valid,
        execution_brief_present: classification.execution_brief_present,
        evidence_complete: classification.evidence_complete,
        raw_value_type: classification.raw_value_type,
        raw_value: classification.raw_value,
        article_opportunity_detected: classification.article_opportunity_detected,
        opportunity_type: classification.opportunity_type,
        improvement_type: classification.improvement_type,
        human_required: classification.human_required,
        research_required: classification.research_required,
        approved: classification.approved,
        repository_configured: classification.repository_configured,
        execution_profile_configured: classification.execution_profile_configured,
        executable_rule_result: classification.executable_rule_result,
        manual_rule_result: classification.manual_rule_result,
        preparation_rule_result: classification.preparation_rule_result,
        matched_classification_rule: classification.matched_classification_rule,
        classification_reason: classification.classification_reason,
        normalized_value_score: diagnostic.normalized_value_score,
        actionability_multiplier: classification.actionability_multiplier,
        category_multiplier: classification.category_multiplier,
        tab_score_revenue: diagnostic.tab_score_revenue,
        tab_score_learning: diagnostics_by_mode.dig("learning")&.find { |row| row.item.stable_id == item.stable_id }&.tab_score_learning,
        tab_score_balanced: diagnostics_by_mode.dig("balanced")&.find { |row| row.item.stable_id == item.stable_id }&.tab_score_balanced,
        included_in_main_ranking: classification.included_in_main_ranking,
        exclusion_reason: classification.exclusion_reason,
        final_rank_revenue: ranks_by_mode.dig("revenue", item.stable_id),
        final_rank_learning: ranks_by_mode.dig("learning", item.stable_id),
        final_rank_balanced: ranks_by_mode.dig("balanced", item.stable_id)
      }
    end

    rows.each do |row|
      puts row.map { |key, value| "#{key}=#{format_value.call(value)}" }.join(" ")
    end

    summary = {
      total_checked: raw_items.size,
      main_ranking: rows.count { |row| row[:included_in_main_ranking] },
      executable: rows.count { |row| row[:candidate_category] == "executable_improvement" },
      manual: rows.count { |row| row[:candidate_category] == "manual_action" },
      preparation: rows.count { |row| row[:candidate_category] == "preparation" },
      unspecified: rows.count { |row| row[:candidate_category] == "unspecified" },
      fallback: rows.count { |row| row[:candidate_category] == "fallback" },
      legacy: rows.count { |row| row[:candidate_category] == "legacy" },
      article_opportunity: rows.count { |row| row[:raw_value_type] == "expected_improvement_score" },
      article_opportunity_top10: rows.count { |row| row[:raw_value_type] == "expected_improvement_score" && row[:final_rank_revenue].to_i.between?(1, 10) },
      target_missing_top10: rows.count { |row| row[:target_valid] == false && row[:final_rank_revenue].to_i.between?(1, 10) },
      legacy_top10: rows.count { |row| row[:candidate_category] == "legacy" && row[:final_rank_revenue].to_i.between?(1, 10) },
      fallback_top10: rows.count { |row| row[:candidate_category] == "fallback" && row[:final_rank_revenue].to_i.between?(1, 10) },
      article_opportunity_executable_count: rows.count { |row| row[:article_opportunity_detected] && row[:candidate_category] == "executable_improvement" },
      article_opportunity_manual_count: rows.count { |row| row[:article_opportunity_detected] && row[:candidate_category] == "manual_action" },
      article_opportunity_preparation_count: rows.count { |row| row[:article_opportunity_detected] && row[:candidate_category] == "preparation" },
      article_opportunity_unspecified_count: rows.count { |row| row[:article_opportunity_detected] && row[:candidate_category] == "unspecified" },
      article_opportunity_main_ranking_count: rows.count { |row| row[:article_opportunity_detected] && row[:included_in_main_ranking] },
      target_missing_main_ranking_count: rows.count { |row| row[:target_valid] == false && row[:included_in_main_ranking] }
    }

    puts "summary #{summary.map { |key, value| "#{key}=#{value}" }.join(' ')}"
  end
end
