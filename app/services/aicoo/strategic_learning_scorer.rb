module Aicoo
  class StrategicLearningScorer
    Result = Data.define(
      :base_score,
      :strategic_score,
      :decision_log_coefficient,
      :final_score,
      :raw_adjusted_score,
      :clamped_adjusted_score,
      :adjustment_rate,
      :guardrail,
      :components,
      :decision_log_samples,
      :decision_dimension_coefficients
    )

    def initialize(subject, base_score: nil, philosophy: StrategicPhilosophy.current, setting: AicooSetting.current)
      @subject = subject
      @base_score = base_score
      @philosophy = philosophy
      @setting = setting
    end

    def call
      components = component_scores
      strategic_score = philosophy.score(components)
      decision_result = DecisionLogCoefficient.new(subject).call
      decision_log_coefficient = guarded_decision_coefficient(decision_result)
      strategic_multiplier = strategic_multiplier_for(strategic_score)
      raw_adjusted_score = raw_adjusted_score_for(strategic_multiplier, decision_log_coefficient)
      clamped_adjusted_score = clamped_score(raw_adjusted_score)
      adjustment_rate = adjustment_rate_for(clamped_adjusted_score)
      guardrail = guardrail_for(
        strategic_score:,
        decision_log_coefficient:,
        raw_adjusted_score:,
        clamped_adjusted_score:,
        adjustment_rate:,
        decision_result:
      )

      Result.new(
        base_score: base_score.to_d.round(2),
        strategic_score:,
        decision_log_coefficient:,
        final_score: clamped_adjusted_score,
        raw_adjusted_score:,
        clamped_adjusted_score:,
        adjustment_rate:,
        guardrail:,
        components:,
        decision_log_samples: decision_result.samples,
        decision_dimension_coefficients: decision_result.dimension_coefficients
      )
    end

  private

    attr_reader :subject, :philosophy, :setting

    def base_score
      @base_score || first_existing(:final_score, :strategic_adjusted_score, :opportunity_score, :expected_value_yen) || 0
    end

    def component_scores
      {
        short_term_profit: money_score(first_existing(:expected_profit_yen, :immediate_value_yen, :expected_value_yen)),
        long_term_profit: long_term_profit_score,
        learning: learning_score,
        automation: automation_score,
        exploration: exploration_score
      }
    end

    def long_term_profit_score
      score = money_score(first_existing(:expected_total_value_yen, :final_expected_value_yen, :expected_value_yen))
      score += numeric_score(:strategic_value_score, divisor: 1)
      clamp(score / 2)
    end

    def learning_score
      score = money_score(first_existing(:expected_learning_value_yen))
      score += 55 if value_for(:action_type).in?(%w[data_preparation learning_improvement opportunity_validation])
      score += 45 if value_for(:opportunity_type).in?(%w[lp_test content_test serp_research])
      clamp(score)
    end

    def automation_score
      score = numeric_score(:risk_reduction_score, divisor: 1)
      text = "#{value_for(:action_type)} #{value_for(:title)} #{value_for(:description)}".downcase
      score += 60 if text.match?(/automation|自動化|codex|executor|api|batch/)
      clamp(score)
    end

    def exploration_score
      score = 0.to_d
      score += 65 if value_for(:generation_source).in?(%w[opportunity_discovery learning_report ai_insight])
      score += 70 if subject.is_a?(OpportunityDiscoveryItem)
      score += 20 if value_for(:source_type).present? && value_for(:source_type) != "owner_discovery"
      clamp(score)
    end

    def strategic_multiplier_for(strategic_score)
      return 1.to_d unless setting.strategic_learning_enabled?
      return 1.to_d if strategic_score.to_d.zero?

      [ [ (strategic_score.to_d / 50.to_d), 1.0.to_d ].max, 1.8.to_d ].min
    end

    def guarded_decision_coefficient(decision_result)
      return 1.to_d unless setting.strategic_learning_enabled?

      coefficient = decision_result.coefficient.to_d
      min_count = setting.strategic_learning_decision_log_min_count.to_i
      return coefficient if min_count.zero? || decision_result.samples >= min_count

      confidence = decision_result.samples.to_d / min_count.to_d
      (1.to_d + ((coefficient - 1.to_d) * confidence)).round(3)
    end

    def raw_adjusted_score_for(strategic_multiplier, decision_log_coefficient)
      return base_score.to_d.round(2) unless setting.strategic_learning_enabled?

      multiplier = strategic_multiplier.to_d * decision_log_coefficient.to_d
      multiplier = 1.to_d + ((multiplier - 1.to_d) * 0.5.to_d) if high_risk_boost?(multiplier)
      (base_score.to_d * multiplier).round(2)
    end

    def clamped_score(raw_adjusted_score)
      return base_score.to_d.round(2) unless setting.strategic_learning_enabled?

      min_score = base_score.to_d * (1.to_d - setting.strategic_learning_max_penalty_rate.to_d)
      max_score = base_score.to_d * (1.to_d + setting.strategic_learning_max_boost_rate.to_d)
      [ [ raw_adjusted_score.to_d, min_score ].max, max_score ].min.round(2)
    end

    def adjustment_rate_for(adjusted_score)
      return 0.to_d if base_score.to_d.zero?

      ((adjusted_score.to_d - base_score.to_d) / base_score.to_d).round(4)
    end

    def guardrail_for(strategic_score:, decision_log_coefficient:, raw_adjusted_score:, clamped_adjusted_score:, adjustment_rate:, decision_result:)
      warning_reasons = []
      warning_reasons << "補正率がwarning thresholdを超えています" if adjustment_rate.abs >= setting.strategic_learning_warning_threshold_rate.to_d
      if decision_result.samples < setting.strategic_learning_decision_log_min_count.to_i && decision_log_coefficient.to_d != decision_result.coefficient.to_d
        warning_reasons << "Decision Log件数が少ないため補正を弱めました"
      end
      warning_reasons << "high risk候補がboostされています" if high_risk? && clamped_adjusted_score.to_d > base_score.to_d
      warning_reasons << "base_scoreが低い候補のboostです" if base_score.to_d < 1_000.to_d && clamped_adjusted_score.to_d > base_score.to_d
      warning_reasons << "Strategic Philosophy Weightが極端に偏っています" if setting.strategic_weights_extremely_skewed?
      warning_reasons << "補正上限/下限でclampしました" if raw_adjusted_score.to_d != clamped_adjusted_score.to_d

      {
        "base_score" => base_score.to_d.round(2).to_s,
        "strategic_score" => strategic_score.to_s,
        "decision_log_coefficient" => decision_log_coefficient.to_s,
        "raw_decision_log_coefficient" => decision_result.coefficient.to_s,
        "raw_adjusted_score" => raw_adjusted_score.to_s,
        "clamped_adjusted_score" => clamped_adjusted_score.to_s,
        "adjustment_rate" => adjustment_rate.to_s,
        "max_boost_rate" => setting.strategic_learning_max_boost_rate.to_s,
        "max_penalty_rate" => setting.strategic_learning_max_penalty_rate.to_s,
        "warning" => warning_reasons.any?,
        "warning_reason" => warning_reasons.join(" / "),
        "decision_log_count" => decision_result.samples,
        "enabled" => setting.strategic_learning_enabled?
      }
    end

    def high_risk_boost?(multiplier)
      high_risk? && multiplier.to_d > 1.to_d
    end

    def high_risk?
      value_for(:risk_level).to_s == "high"
    end

    def money_score(value)
      return 0.to_d if value.blank?

      [ [ value.to_d / 1_000.to_d, 0.to_d ].max, 100.to_d ].min
    end

    def numeric_score(attribute, divisor:)
      value = first_existing(attribute)
      return 0.to_d if value.blank?

      clamp(value.to_d / divisor.to_d)
    end

    def first_existing(*attributes)
      attributes.each do |attribute|
        value = value_for(attribute)
        return value if value.present?
      end

      nil
    end

    def value_for(attribute)
      return subject.public_send(attribute) if subject.respond_to?(attribute)
      return subject.metadata.to_h[attribute.to_s] if subject.respond_to?(:metadata)

      nil
    end

    def clamp(value)
      [ [ value.to_d, 0.to_d ].max, 100.to_d ].min
    end
  end
end
