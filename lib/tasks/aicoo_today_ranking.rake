namespace :aicoo do
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
      fallback_top10: rows.count { |row| row[:candidate_category] == "fallback" && row[:final_rank_revenue].to_i.between?(1, 10) }
    }

    puts "summary #{summary.map { |key, value| "#{key}=#{value}" }.join(' ')}"
  end
end
