module Aicoo
  class OwnerDecisionSummary
    Summary = Data.define(
      :generated_at,
      :today_count,
      :last_7_days_count,
      :last_30_days_count,
      :counts_by_decision_type,
      :action_type_adoption_rates,
      :risk_level_execution_rates,
      :recent_logs
    )
    RateSummary = Data.define(:label, :total_count, :positive_count, :rate)

    def call
      logs_30_days = OwnerDecisionLog.last_30_days

      Summary.new(
        generated_at: Time.current,
        today_count: OwnerDecisionLog.today.count,
        last_7_days_count: OwnerDecisionLog.last_7_days.count,
        last_30_days_count: logs_30_days.count,
        counts_by_decision_type: counts_by_decision_type(logs_30_days),
        action_type_adoption_rates: action_type_adoption_rates(logs_30_days),
        risk_level_execution_rates: risk_level_execution_rates(logs_30_days),
        recent_logs: OwnerDecisionLog.includes(:business, :queue_item).recent.limit(10)
      )
    end

    private

    def counts_by_decision_type(scope)
      grouped_counts = scope.group(:decision_type).count
      OwnerDecisionLog::DECISION_TYPES.index_with { |type| grouped_counts.fetch(type, 0) }
    end

    def action_type_adoption_rates(scope)
      grouped_counts = scope
        .where.not(action_type: [ nil, "" ])
        .group(:action_type, :decision_type)
        .count
      grouped_by_action_type = grouped_counts.group_by do |(action_type, _decision_type), _count|
        action_type
      end

      grouped_by_action_type.map do |action_type, rows|
        total_count = rows.sum { |_key, count| count }
        positive_count = rows.sum do |(_grouped_action_type, decision_type), count|
          decision_type.in?(OwnerDecisionLog::POSITIVE_DECISIONS) ? count : 0
        end
        RateSummary.new(
          label: action_type,
          total_count:,
          positive_count:,
          rate: ratio(positive_count, total_count)
        )
      end.sort_by { |summary| [ -summary.rate, -summary.total_count, summary.label ] }.first(10)
    end

    def risk_level_execution_rates(scope)
      grouped_counts = scope
        .where.not(risk_level: [ nil, "" ])
        .group(:risk_level, :decision_type)
        .count
      grouped_by_risk_level = grouped_counts.group_by do |(risk_level, _decision_type), _count|
        risk_level
      end

      grouped_by_risk_level.map do |risk_level, rows|
        total_count = rows.sum { |_key, count| count }
        positive_count = rows.sum do |(_grouped_risk_level, decision_type), count|
          decision_type.in?(OwnerDecisionLog::EXECUTION_DECISIONS) ? count : 0
        end
        RateSummary.new(
          label: risk_level,
          total_count:,
          positive_count:,
          rate: ratio(positive_count, total_count)
        )
      end.sort_by { |summary| [ -summary.rate, summary.label ] }
    end

    def ratio(numerator, denominator)
      return 0.to_d if denominator.to_i.zero?

      (numerator.to_d / denominator.to_d).round(3)
    end
  end
end
