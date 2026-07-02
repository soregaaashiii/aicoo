module Aicoo
  class BusinessPlaybookBuilder
    Result = Data.define(:updated_count, :playbooks)

    def self.update_all!(collect_records: true)
      playbooks = []
      updated_count = 0
      Business.real_businesses.find_each do |business|
        playbook = new(business).update!
        updated_count += 1
        playbooks << playbook if collect_records
      end
      Result.new(updated_count:, playbooks:)
    end

    def initialize(business)
      @business = business
    end

    def update!
      playbook = business.business_playbook || business.build_business_playbook
      action_summary = action_type_summary
      opportunity_summary = opportunity_type_summary
      task_summary = action_expansion_task_summary
      analysis_summary = analysis_source_summary
      playbook.update!(
        sample_count: total_sample_count(action_summary, opportunity_summary, task_summary, analysis_summary),
        confidence_score: confidence_for(action_summary, opportunity_summary, task_summary, analysis_summary),
        top_action_type: top_type(action_summary),
        worst_action_type: worst_type(action_summary),
        top_opportunity_type: top_type(opportunity_summary),
        worst_opportunity_type: worst_type(opportunity_summary),
        average_roi: average(action_summary.values.pluck("roi")),
        average_actual_profit_yen: average(action_summary.values.pluck("average_actual_profit_yen")),
        average_practicality_score: average(action_summary.values.pluck("average_practicality_score")),
        average_evidence_score: average(action_summary.values.pluck("average_evidence_score")),
        action_type_summary: action_summary,
        opportunity_type_summary: opportunity_summary,
        metadata: {
          "generated_from" => %w[action_results revenue_events owner_decision_logs action_execution_logs owner_execution_queue_items codex_prompt_drafts opportunity_discovery_items action_candidates],
          "recommended_action_types" => recommended_types(action_summary),
          "weak_action_types" => weak_types(action_summary),
          "task_summary" => task_summary,
          "recommended_tasks" => recommended_types(task_summary),
          "weak_tasks" => weak_types(task_summary),
          "analysis_summary" => analysis_summary,
          "recommended_analysis_sources" => recommended_types(analysis_summary),
          "weak_analysis_sources" => weak_types(analysis_summary),
          "business_type" => business.business_type,
          "business_type_action_summary" => business_type_action_summary
        },
        last_calculated_at: Time.current
      )
      playbook
    end

    private

    attr_reader :business

    def action_type_summary
      action_types = (business.action_candidates.distinct.pluck(:action_type) + OwnerDecisionLog.where(business:).distinct.pluck(:action_type)).compact_blank.uniq
      action_types.index_with { |action_type| action_type_row(action_type) }
    end

    def business_type_action_summary
      businesses = Business.real_businesses.where(business_type: business.business_type)
      action_types = ActionCandidate.where(business: businesses).distinct.pluck(:action_type).compact_blank
      action_types.index_with do |action_type|
        candidates = ActionCandidate.where(business: businesses, action_type:)
        results = ActionResult.joins(:action_candidate).where(
          business: businesses,
          action_candidates: { action_type: }
        )
        {
          "type" => action_type,
          "business_type" => business.business_type,
          "candidate_count" => candidates.count,
          "result_count" => results.count,
          "success_rate" => rate(results.where("actual_profit_yen > 0").count, results.count),
          "average_expected_profit_yen" => average(candidates.pluck(:expected_profit_yen)),
          "average_actual_profit_yen" => average(results.pluck(:actual_profit_yen))
        }.transform_values { |value| value.respond_to?(:round) ? value.to_d.round(4).to_s : value }
      end
    end

    def action_type_row(action_type)
      candidates = business.action_candidates.where(action_type:)
      decisions = OwnerDecisionLog.where(business:, action_type:)
      results = ActionResult.joins(:action_candidate).where(business:, action_candidates: { action_type: })
      executions = ActionExecutionLog.joins(:action_candidate).where(business:, action_candidates: { action_type: })
      revenue = RevenueEvent.joins(:action_candidate).where(business:, action_candidates: { action_type: }).revenue.sum(:amount)
      expense = RevenueEvent.joins(:action_candidate).where(business:, action_candidates: { action_type: }).expense.sum(:amount)
      actual_profit = results.sum(:actual_profit_yen)
      expected_profit = candidates.sum(:expected_profit_yen)
      total_decisions = decisions.count
      execution_count = executions.count
      sample_count = [ results.count, total_decisions, execution_count ].sum
      average_actual_profit = results.count.positive? ? actual_profit.to_d / results.count : 0.to_d
      roi = expense.to_i.positive? ? (revenue.to_d - expense.to_d) / expense.to_d : nil
      result_rows = result_metric_rows(results)

      {
        "type" => action_type,
        "execution_count" => execution_count,
        "adoption_rate" => rate(decisions.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count, total_decisions),
        "reject_rate" => rate(decisions.where(decision_type: "reject").count, total_decisions),
        "skip_rate" => rate(decisions.where(decision_type: "skip").count, total_decisions),
        "execution_rate" => rate(decisions.where(decision_type: OwnerDecisionLog::EXECUTION_DECISIONS).count, total_decisions),
        "average_expected_profit_yen" => average(candidates.pluck(:expected_profit_yen)),
        "average_actual_profit_yen" => average_actual_profit,
        "roi" => roi,
        "average_hours" => average(candidates.pluck(:expected_hours)),
        "average_practicality_score" => average(candidates.pluck(:practicality_score)),
        "average_evidence_score" => average(candidates.pluck(:metadata).map { |metadata| metadata.to_h.dig("evidence", "score").to_d }),
        "average_engagement_delta" => average(result_rows.map { |row| engagement_delta_for_row(row) }),
        "average_navigation_delta" => average(result_rows.map { |row| navigation_delta_for_row(row) }),
        "average_conversion_delta" => average(result_rows.map { |row| conversion_delta_for_row(row) }),
        "decision_log_coefficient" => decision_log_coefficient(decisions),
        "success_rate" => rate(results.where("actual_profit_yen > 0").count, results.count),
        "sample_count" => sample_count,
        "score" => playbook_score(
          success_rate: rate(results.where("actual_profit_yen > 0").count, results.count),
          adoption_rate: rate(decisions.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count, total_decisions),
          average_actual_profit:,
          expected_profit:
        )
      }.transform_values { |value| value.respond_to?(:round) ? value.to_d.round(4).to_s : value }
    end

    def opportunity_type_summary
      types = business.opportunity_discovery_items.distinct.pluck(:opportunity_type).compact_blank
      types.index_with { |opportunity_type| opportunity_type_row(opportunity_type) }
    end

    def opportunity_type_row(opportunity_type)
      opportunities = business.opportunity_discovery_items.where(opportunity_type:)
      candidates = ActionCandidate.where(id: opportunities.where.not(action_candidate_id: nil).select(:action_candidate_id))
      results = ActionResult.where(action_candidate_id: candidates.select(:id))
      decisions = OwnerDecisionLog.where(business:, opportunity_type:)
      actual_profit = results.sum(:actual_profit_yen)
      sample_count = opportunities.count + decisions.count + results.count

      {
        "type" => opportunity_type,
        "opportunity_count" => opportunities.count,
        "success_rate" => rate(results.where("actual_profit_yen > 0").count, results.count),
        "adoption_rate" => rate(decisions.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count, decisions.count),
        "average_expected_value_yen" => average(opportunities.pluck(:expected_value_yen)),
        "average_actual_profit_yen" => results.count.positive? ? actual_profit.to_d / results.count : 0.to_d,
        "sample_count" => sample_count,
        "score" => playbook_score(
          success_rate: rate(results.where("actual_profit_yen > 0").count, results.count),
          adoption_rate: rate(decisions.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count, decisions.count),
          average_actual_profit: results.count.positive? ? actual_profit.to_d / results.count : 0.to_d,
          expected_profit: opportunities.sum(:expected_value_yen)
        )
      }.transform_values { |value| value.respond_to?(:round) ? value.to_d.round(4).to_s : value }
    end

    def action_expansion_task_summary
      task_names.index_with { |task| action_expansion_task_row(task) }
    end

    def task_names
      names = business.action_candidates.pluck(:metadata).flat_map do |metadata|
        Array(metadata.to_h.dig("action_expansion", "recommended_tasks"))
      end
      names += OwnerDecisionLog.where(business:).pluck(:metadata).flat_map { |metadata| Array(metadata.to_h["action_expansion_tasks"]) }
      names += ActionResult.where(business:).pluck(:metadata).flat_map { |metadata| Array(metadata.to_h.dig("action_expansion_learning", "available_tasks")) }
      names.compact_blank.uniq
    end

    def action_expansion_task_row(task)
      candidates = business.action_candidates.pluck(:expected_profit_yen, :practicality_score, :metadata).select do |(_expected_profit, _practicality_score, metadata)|
        Array(metadata.to_h.dig("action_expansion", "recommended_tasks")).include?(task)
      end
      decisions = OwnerDecisionLog.where(business:).pluck(:decision_type, :metadata).select do |(_decision_type, metadata)|
        Array(metadata.to_h["action_expansion_tasks"]).include?(task)
      end
      results = ActionResult.where(business:).pluck(*result_metric_columns).select do |row|
        Array(row.last.to_h.dig("action_expansion_learning", "available_tasks")).include?(task)
      end
      executed_results = results.select do |result|
        Array(result.last.to_h.dig("action_expansion_learning", "executed_tasks")).include?(task)
      end
      total_decisions = decisions.size
      sample_count = candidates.size + decisions.size + results.size
      actual_profit = executed_results.sum { |row| row[0].to_i }
      expected_profit = candidates.sum { |row| row[0].to_i }
      average_actual_profit = executed_results.any? ? actual_profit.to_d / executed_results.size : 0.to_d
      success_rate = rate(executed_results.count { |row| row[0].to_i.positive? }, executed_results.size)
      adoption_rate = rate(decisions.count { |row| OwnerDecisionLog::POSITIVE_DECISIONS.include?(row[0]) }, total_decisions)
      completion_rate = rate(executed_results.size, results.size)
      roi = expected_profit.positive? ? actual_profit.to_d / expected_profit.to_d : nil

      {
        "type" => task,
        "task" => task,
        "candidate_count" => candidates.size,
        "decision_count" => total_decisions,
        "result_count" => results.size,
        "executed_result_count" => executed_results.size,
        "adoption_rate" => adoption_rate,
        "reject_rate" => rate(decisions.count { |row| row[0] == "reject" }, total_decisions),
        "skip_rate" => rate(decisions.count { |row| row[0] == "skip" }, total_decisions),
        "completion_rate" => completion_rate,
        "success_rate" => success_rate,
        "average_expected_profit_yen" => average(candidates.map { |row| row[0] }),
        "average_actual_profit_yen" => average_actual_profit,
        "roi" => roi,
        "average_practicality_score" => average(candidates.map { |row| row[1] }),
        "average_evidence_score" => average(candidates.map { |row| row[2].to_h.dig("evidence", "score").to_d }),
        "average_engagement_delta" => average(executed_results.map { |row| engagement_delta_for_row(row) }),
        "average_navigation_delta" => average(executed_results.map { |row| navigation_delta_for_row(row) }),
        "average_conversion_delta" => average(executed_results.map { |row| conversion_delta_for_row(row) }),
        "sample_count" => sample_count,
        "score" => playbook_score(
          success_rate:,
          adoption_rate:,
          average_actual_profit:,
          expected_profit:
        )
      }.transform_values { |value| value.respond_to?(:round) ? value.to_d.round(4).to_s : value }
    end

    def analysis_source_summary
      business.analysis_candidates.distinct.pluck(:analysis_source).compact_blank.index_with do |source|
        analysis_source_row(source)
      end
    end

    def analysis_source_row(source)
      candidates = business.analysis_candidates.where(analysis_source: source)
      total_count = candidates.count
      completed_count = candidates.where(status: "completed").count
      skipped_count = candidates.where(status: "skipped").count
      failed_count = candidates.where(status: "failed").count
      expected_value = candidates.sum(:expected_value_yen)
      estimated_cost = candidates.sum(:estimated_cost_yen)
      average_roi = average(candidates.pluck(:roi))
      roi = estimated_cost.to_d.positive? ? expected_value.to_d / estimated_cost.to_d : average_roi
      completion_rate = rate(completed_count, total_count)
      skip_rate = rate(skipped_count, total_count)
      failure_rate = rate(failed_count, total_count)

      {
        "type" => source,
        "source" => source,
        "candidate_count" => total_count,
        "completed_count" => completed_count,
        "skipped_count" => skipped_count,
        "failed_count" => failed_count,
        "completion_rate" => completion_rate,
        "skip_rate" => skip_rate,
        "failure_rate" => failure_rate,
        "average_expected_value_yen" => average(candidates.pluck(:expected_value_yen)),
        "average_estimated_cost_yen" => average(candidates.pluck(:estimated_cost_yen)),
        "roi" => roi,
        "average_confidence" => average(candidates.pluck(:confidence)),
        "sample_count" => total_count,
        "score" => ((completion_rate.to_d * 30) + ([ roi.to_d, 100 ].min * 0.5) - (failure_rate.to_d * 20)).round(2)
      }.transform_values { |value| value.respond_to?(:round) ? value.to_d.round(4).to_s : value }
    end

    def playbook_score(success_rate:, adoption_rate:, average_actual_profit:, expected_profit:)
      revenue_signal = expected_profit.to_d.positive? ? [ average_actual_profit.to_d / expected_profit.to_d, 1.to_d ].min : 0.to_d
      ((success_rate.to_d * 40) + (adoption_rate.to_d * 30) + (revenue_signal * 30)).round(2)
    end

    def decision_log_coefficient(decisions)
      total = decisions.count
      return 1.to_d if total < Aicoo::DecisionLogCoefficient::MIN_SAMPLE_SIZE

      positive = decisions.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count
      negative = decisions.where(decision_type: %w[reject skip]).count
      coefficient = 1.to_d + (((positive.to_d / total) - (negative.to_d / total)) * 0.25.to_d)
      [ [ coefficient, Aicoo::DecisionLogCoefficient::MIN_COEFFICIENT ].max, Aicoo::DecisionLogCoefficient::MAX_COEFFICIENT ].min
    end

    def confidence_for(action_summary, opportunity_summary, task_summary, analysis_summary)
      samples = total_sample_count(action_summary, opportunity_summary, task_summary, analysis_summary)
      [ samples * 4, 100 ].min.to_d
    end

    def total_sample_count(action_summary, opportunity_summary, task_summary, analysis_summary)
      action_summary.values.sum { |row| row["sample_count"].to_i } +
        opportunity_summary.values.sum { |row| row["sample_count"].to_i } +
        task_summary.values.sum { |row| row["sample_count"].to_i } +
        analysis_summary.values.sum { |row| row["sample_count"].to_i }
    end

    def top_type(summary)
      summary.values.max_by { |row| row["score"].to_d }&.fetch("type", nil)
    end

    def worst_type(summary)
      meaningful = summary.values.select { |row| row["sample_count"].to_i.positive? }
      meaningful.min_by { |row| row["score"].to_d }&.fetch("type", nil)
    end

    def recommended_types(summary)
      summary.values.sort_by { |row| -row["score"].to_d }.first(3).map { |row| row["type"] }
    end

    def weak_types(summary)
      summary.values.select { |row| row["sample_count"].to_i.positive? }.sort_by { |row| row["score"].to_d }.first(3).map { |row| row["type"] }
    end

    def average(values)
      values = values.compact.map(&:to_d)
      return 0.to_d if values.empty?

      values.sum / values.size
    end

    def result_metric_rows(scope)
      scope.pluck(*result_metric_columns)
    end

    def result_metric_columns
      %i[
        actual_profit_yen
        actual_pageviews_delta
        actual_sessions_delta
        actual_phone_clicks_delta
        actual_map_clicks_delta
        actual_affiliate_clicks_delta
        metadata
      ]
    end

    def engagement_delta_for_row(row)
      value = result_row_metadata(row).dig("engagement", "average_engagement_time_delta_seconds")
      return value.to_d if value.present?

      result_row_pageviews_delta(row) - result_row_sessions_delta(row)
    end

    def navigation_delta_for_row(row)
      value = result_row_metadata(row).dig("engagement", "views_per_session_delta")
      return value.to_d if value.present?
      return 0.to_d if result_row_sessions_delta(row).zero?

      result_row_pageviews_delta(row) / result_row_sessions_delta(row)
    end

    def conversion_delta_for_row(row)
      value = result_row_metadata(row).dig("engagement", "conversion_rate_delta")
      return value.to_d if value.present?
      return 0.to_d if result_row_sessions_delta(row).zero?

      (row[3].to_i + row[4].to_i + row[5].to_i).to_d / result_row_sessions_delta(row)
    end

    def result_row_pageviews_delta(row)
      row[1].to_d
    end

    def result_row_sessions_delta(row)
      row[2].to_d
    end

    def result_row_metadata(row)
      row[6].to_h
    end

    def rate(numerator, denominator)
      return 0.to_d if denominator.to_i.zero?

      numerator.to_d / denominator.to_d
    end
  end
end
