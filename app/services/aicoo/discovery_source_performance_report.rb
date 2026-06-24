module Aicoo
  class DiscoverySourcePerformanceReport
    MIN_SAMPLE_SIZE = 2

    Result = Data.define(
      :generated_at,
      :source_summaries,
      :strongest_sources,
      :weakest_sources,
      :conversion_funnel,
      :warnings
    )
    SourceSummary = Data.define(
      :source_type,
      :opportunities_count,
      :candidates_count,
      :executions_count,
      :results_count,
      :success_count,
      :failure_count,
      :total_predicted_profit,
      :total_actual_profit,
      :average_actual_profit,
      :average_prediction_error,
      :opportunity_to_candidate_rate,
      :candidate_to_execution_rate,
      :execution_to_result_rate,
      :overall_success_rate
    )
    FunnelItem = Data.define(
      :source_type,
      :opportunities_count,
      :candidates_count,
      :executions_count,
      :results_count,
      :opportunity_to_candidate_rate,
      :candidate_to_execution_rate,
      :execution_to_result_rate
    )

    def call
      Result.new(
        generated_at: Time.current,
        source_summaries: summaries,
        strongest_sources: strongest_sources,
        weakest_sources: weakest_sources,
        conversion_funnel: conversion_funnel,
        warnings: warnings
      )
    end

    private

    def summaries
      @summaries ||= source_types.map { |source_type| build_summary(source_type) }
    end

    def build_summary(source_type)
      opportunities = opportunities_for(source_type)
      candidates = candidates_for(opportunities)
      executions = executions_for(candidates)
      results = results_for(candidates)
      predicted_profit = results.sum { |result| result.predicted_expected_profit_yen.to_i }
      actual_profit = results.sum { |result| result.actual_profit_yen.to_i }
      error_rates = results.filter_map { |result| prediction_error_rate(result) }

      SourceSummary.new(
        source_type:,
        opportunities_count: opportunities.size,
        candidates_count: candidates.size,
        executions_count: executions.size,
        results_count: results.size,
        success_count: results.count { |result| result.actual_profit_yen.to_i.positive? },
        failure_count: results.count { |result| result.actual_profit_yen.to_i <= 0 },
        total_predicted_profit: predicted_profit,
        total_actual_profit: actual_profit,
        average_actual_profit: average(actual_profit, results.size),
        average_prediction_error: average_decimal(error_rates),
        opportunity_to_candidate_rate: rate(candidates.size, opportunities.size),
        candidate_to_execution_rate: rate(executions.size, candidates.size),
        execution_to_result_rate: rate(results.size, executions.size),
        overall_success_rate: rate(results.count { |result| result.actual_profit_yen.to_i.positive? }, results.size)
      )
    end

    def strongest_sources
      eligible_summaries.sort_by do |summary|
        [ -summary.total_actual_profit.to_i, -summary.overall_success_rate.to_d ]
      end.first(5)
    end

    def weakest_sources
      eligible_summaries.sort_by do |summary|
        [ summary.overall_success_rate.to_d, summary.total_actual_profit.to_i ]
      end.first(5)
    end

    def conversion_funnel
      summaries.map do |summary|
        FunnelItem.new(
          source_type: summary.source_type,
          opportunities_count: summary.opportunities_count,
          candidates_count: summary.candidates_count,
          executions_count: summary.executions_count,
          results_count: summary.results_count,
          opportunity_to_candidate_rate: summary.opportunity_to_candidate_rate,
          candidate_to_execution_rate: summary.candidate_to_execution_rate,
          execution_to_result_rate: summary.execution_to_result_rate
        )
      end
    end

    def warnings
      [].tap do |items|
        items << "Discovery Sourceの評価済みResultが不足しています。" if summaries.sum(&:results_count) < MIN_SAMPLE_SIZE
        weakest_sources.each do |summary|
          next unless summary.overall_success_rate.to_d < 0.4.to_d

          items << "#{summary.source_type} の成功率が低下しています。"
        end
        summaries.each do |summary|
          next unless summary.results_count >= MIN_SAMPLE_SIZE && summary.total_actual_profit.to_i.negative?

          items << "#{summary.source_type} の実績利益がマイナスです。"
        end
      end
    end

    def eligible_summaries
      summaries.select { |summary| summary.results_count >= MIN_SAMPLE_SIZE }
    end

    def source_types
      (OpportunityDiscoveryItem::SOURCE_TYPES + OpportunityDiscoveryItem.distinct.pluck(:source_type)).compact.uniq
    end

    def opportunities_for(source_type)
      OpportunityDiscoveryItem.includes(action_candidate: %i[action_execution action_result]).where(source_type:).to_a
    end

    def candidates_for(opportunities)
      opportunities.filter_map(&:action_candidate).uniq
    end

    def executions_for(candidates)
      candidates.filter_map(&:action_execution).uniq
    end

    def results_for(candidates)
      candidates.filter_map(&:action_result).uniq
    end

    def prediction_error_rate(result)
      return result.prediction_error_rate.to_d if result.prediction_error_rate.present?

      predicted = result.predicted_expected_profit_yen.to_i
      return if predicted.zero?

      (predicted - result.actual_profit_yen.to_i).abs.to_d / predicted
    end

    def average(total, count)
      return 0 if count.zero?

      (total.to_d / count).round
    end

    def average_decimal(values)
      return nil if values.empty?

      values.sum.to_d / values.size
    end

    def rate(numerator, denominator)
      return 0.to_d if denominator.to_i.zero?

      numerator.to_d / denominator
    end
  end
end
