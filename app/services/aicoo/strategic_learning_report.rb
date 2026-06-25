module Aicoo
  class StrategicLearningReport
    Report = Data.define(
      :generated_at,
      :philosophy_weights,
      :decision_correction_rate,
      :learning_correction_rate,
      :strategic_alignment_rate,
      :top_approved_action_types,
      :top_rejected_action_types,
      :top_skipped_action_types,
      :execution_rate_by_risk_level,
      :decision_coefficients,
      :high_value_skipped_logs,
      :contrary_decision_count,
      :guardrail_settings,
      :guardrail_warning_today_count,
      :guardrail_warning_7_days_count,
      :guardrail_warning_30_days_count,
      :largest_adjustments,
      :high_risk_boosted,
      :weakened_decision_log_count,
      :max_adjustment_rate
    )
    Rate = Data.define(:label, :count, :rate, :coefficient)

    def call
      logs = OwnerDecisionLog.last_30_days
      Report.new(
        generated_at: Time.current,
        philosophy_weights: StrategicPhilosophy.current.weights,
        decision_correction_rate: decision_correction_rate(logs),
        learning_correction_rate: learning_correction_rate,
        strategic_alignment_rate: strategic_alignment_rate(logs),
        top_approved_action_types: top_action_types(logs, OwnerDecisionLog::POSITIVE_DECISIONS),
        top_rejected_action_types: top_action_types(logs, [ "reject" ]),
        top_skipped_action_types: top_action_types(logs, [ "skip" ]),
        execution_rate_by_risk_level: execution_rate_by_risk_level(logs),
        decision_coefficients: decision_coefficients(logs),
        high_value_skipped_logs: logs.where(decision_type: %w[reject skip])
                                   .where("expected_value_yen >= ?", 50_000)
                                   .recent
                                   .limit(10),
        contrary_decision_count: contrary_decision_count(logs),
        guardrail_settings: guardrail_settings,
        guardrail_warning_today_count: guardrail_warning_count(ActionCandidate.where(created_at: Time.current.all_day)),
        guardrail_warning_7_days_count: guardrail_warning_count(ActionCandidate.where(created_at: 7.days.ago..)),
        guardrail_warning_30_days_count: guardrail_warning_count(ActionCandidate.where(created_at: 30.days.ago..)),
        largest_adjustments: largest_adjustments,
        high_risk_boosted: high_risk_boosted,
        weakened_decision_log_count: weakened_decision_log_count,
        max_adjustment_rate: max_adjustment_rate
      )
    end

    private

    def top_action_types(logs, decisions)
      logs.where(decision_type: decisions)
          .where.not(action_type: [ nil, "" ])
          .group(:action_type)
          .count
          .sort_by { |action_type, count| [ -count, action_type ] }
          .first(5)
    end

    def execution_rate_by_risk_level(logs)
      logs.where.not(risk_level: [ nil, "" ])
          .group(:risk_level)
          .count
          .map do |risk_level, count|
        executed = logs.where(risk_level:, decision_type: OwnerDecisionLog::EXECUTION_DECISIONS).count
        Rate.new(
          label: risk_level,
          count:,
          rate: ratio(executed, count),
          coefficient: nil
        )
      end
    end

    def decision_coefficients(logs)
      %i[action_type opportunity_type risk_level generation_source].flat_map do |dimension|
        logs.where.not(dimension => [ nil, "" ])
            .group(dimension)
            .count
            .map do |value, count|
          positive = logs.where(dimension => value, decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count
          rate = ratio(positive, count)
          Rate.new(
            label: "#{dimension}: #{value}",
            count:,
            rate:,
            coefficient: (1.to_d + ((rate - 0.5.to_d) * 0.25.to_d)).round(3)
          )
        end
      end.sort_by { |item| [ -(item.coefficient || 1), -item.count, item.label ] }.first(10)
    end

    def decision_correction_rate(logs)
      return 0.to_d if logs.count.zero?

      adjusted = logs.count { |log| log.metadata.to_h.dig("strategic_learning", "decision_log_coefficient").to_d != 1.to_d }
      ratio(adjusted, logs.count)
    end

    def learning_correction_rate
      return 0.to_d if ActionCandidate.count.zero?

      ratio(ActionCandidate.all.count { |candidate| candidate.metadata.to_h.key?("strategic_learning") }, ActionCandidate.count)
    end

    def strategic_alignment_rate(logs)
      return 1.to_d if logs.count.zero?

      aligned = logs.count { |log| aligned?(log) }
      ratio(aligned, logs.count)
    end

    def aligned?(log)
      strategic_score = log.metadata.to_h.dig("strategic_learning", "strategic_score").to_d
      return true if strategic_score.zero?

      if OwnerDecisionLog::POSITIVE_DECISIONS.include?(log.decision_type)
        strategic_score >= 40
      else
        strategic_score <= 70
      end
    end

    def contrary_decision_count(logs)
      logs.count do |log|
        strategic_score = log.metadata.to_h.dig("strategic_learning", "strategic_score").to_d
        next false if strategic_score.zero?

        (strategic_score >= 70 && log.decision_type.in?(%w[reject skip])) ||
          (strategic_score < 40 && OwnerDecisionLog::POSITIVE_DECISIONS.include?(log.decision_type))
      end
    end

    def ratio(numerator, denominator)
      return 0.to_d if denominator.to_i.zero?

      (numerator.to_d / denominator.to_d).round(3)
    end

    def guardrail_settings
      setting = AicooSetting.current
      {
        enabled: setting.strategic_learning_enabled?,
        max_boost_rate: setting.strategic_learning_max_boost_rate,
        max_penalty_rate: setting.strategic_learning_max_penalty_rate,
        warning_threshold_rate: setting.strategic_learning_warning_threshold_rate,
        decision_log_min_count: setting.strategic_learning_decision_log_min_count
      }
    end

    def guardrail_warning_count(scope)
      scope.count { |candidate| candidate.metadata.to_h.dig("strategic_learning_guardrail", "warning") == true }
    end

    def largest_adjustments
      ActionCandidate.all
                     .sort_by { |candidate| -guardrail_rate(candidate).abs }
                     .first(5)
    end

    def high_risk_boosted
      ActionCandidate.all.select do |candidate|
        guardrail = candidate.metadata.to_h["strategic_learning_guardrail"].to_h
        guardrail.fetch("warning_reason", "").include?("high risk") && guardrail.fetch("adjustment_rate", 0).to_d.positive?
      end.first(5)
    end

    def weakened_decision_log_count
      ActionCandidate.all.count do |candidate|
        guardrail = candidate.metadata.to_h["strategic_learning_guardrail"].to_h
        guardrail.fetch("raw_decision_log_coefficient", "1").to_d != guardrail.fetch("decision_log_coefficient", "1").to_d
      end
    end

    def max_adjustment_rate
      ActionCandidate.all.map { |candidate| guardrail_rate(candidate).abs }.max || 0.to_d
    end

    def guardrail_rate(candidate)
      candidate.metadata.to_h.dig("strategic_learning_guardrail", "adjustment_rate").to_d
    end
  end
end
