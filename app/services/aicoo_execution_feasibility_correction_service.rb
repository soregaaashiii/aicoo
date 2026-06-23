class AicooExecutionFeasibilityCorrectionService
  METADATA_KEY = "execution_feasibility_correction"
  QUANTITY_PATTERN = /(\d+(?:\.\d+)?)(\s*(?:件|本|記事|店舗|個|回))/

  Result = Data.define(
    :applied,
    :summary,
    :source,
    :base_success_probability,
    :adjusted_success_probability,
    :base_expected_hours,
    :adjusted_expected_hours,
    :reason
  )

  def initialize(action_candidate, insight: AicooExecutionFeasibilityInsightService.new.call)
    @action_candidate = action_candidate
    @insight = insight
  end

  def apply!
    summary, source = best_summary
    return record_no_correction("insufficient_data", "実行差分ログが不足しているため補正なし", source) unless summary
    return record_no_correction(summary.feasibility_label, "実行可能性Insightは#{summary.feasibility_label}のため補正なし", source) unless correction_needed?(summary)

    base_values = correction_base_values
    adjusted_success_probability = adjusted_success_probability_for(summary, base_values.fetch(:success_probability))
    adjusted_expected_hours = adjusted_expected_hours_for(summary, base_values.fetch(:expected_hours))
    adjusted_prompt = adjusted_execution_prompt_for(summary, base_values.fetch(:execution_prompt))
    reason = correction_reason(summary)

    action_candidate.success_probability = adjusted_success_probability
    action_candidate.expected_hours = adjusted_expected_hours
    action_candidate.execution_prompt = adjusted_prompt
    action_candidate.evaluation_reason = append_reason(base_values.fetch(:evaluation_reason), reason)
    action_candidate.metadata = action_candidate.metadata.to_h.merge(
      METADATA_KEY => metadata_for(
        applied: true,
        summary:,
        source:,
        base_values:,
        adjusted_success_probability:,
        adjusted_expected_hours:,
        adjusted_prompt:,
        reason:
      )
    )

    Result.new(
      applied: true,
      summary:,
      source:,
      base_success_probability: base_values.fetch(:success_probability),
      adjusted_success_probability:,
      base_expected_hours: base_values.fetch(:expected_hours),
      adjusted_expected_hours:,
      reason:
    )
  end

  private

  attr_reader :action_candidate, :insight

  def best_summary
    [
      [ summary_by_business_action_type, "business_action_type" ],
      [ summary_by_action_type, "action_type" ],
      [ summary_by_business, "business" ],
      [ insight.fetch(:overall), "overall" ]
    ].find { |summary, _source| summary && summary.feasibility_label != "insufficient_data" } ||
      [ insight.fetch(:overall), "overall" ]
  end

  def summary_by_business_action_type
    insight.fetch(:by_business_action_type).find do |summary|
      summary.key == [ action_candidate.business_id, action_candidate.action_type ]
    end
  end

  def summary_by_action_type
    insight.fetch(:by_action_type).find { |summary| summary.key == action_candidate.action_type }
  end

  def summary_by_business
    insight.fetch(:by_business).find { |summary| summary.key == action_candidate.business_id }
  end

  def correction_needed?(summary)
    %w[easy_to_execute over_sized unstable hard_to_execute].include?(summary.feasibility_label)
  end

  def correction_base_values
    prior = action_candidate.metadata.to_h.fetch(METADATA_KEY, {})
    {
      success_probability: base_value_for(prior, "success_probability", action_candidate.success_probability),
      expected_hours: base_value_for(prior, "expected_hours", action_candidate.expected_hours),
      execution_prompt: base_text_for(prior, "execution_prompt", action_candidate.execution_prompt),
      evaluation_reason: base_text_for(prior, "evaluation_reason", action_candidate.evaluation_reason)
    }
  end

  def base_value_for(prior, key, current_value)
    return current_value.to_d unless prior["applied"]

    adjusted_key = "adjusted_#{key}"
    base_key = "base_#{key}"
    return prior[base_key].to_d if prior[adjusted_key].present? && current_value.to_d == prior[adjusted_key].to_d

    current_value.to_d
  end

  def base_text_for(prior, key, current_value)
    return current_value.to_s unless prior["applied"]

    adjusted_key = "adjusted_#{key}"
    base_key = "base_#{key}"
    return prior[base_key].to_s if prior[adjusted_key].present? && current_value.to_s == prior[adjusted_key].to_s

    current_value.to_s
  end

  def adjusted_success_probability_for(summary, base_success_probability)
    delta = case summary.feasibility_label
    when "easy_to_execute" then 0.02
    when "over_sized" then -0.08
    when "unstable" then -0.05
    when "hard_to_execute" then -0.15
    else 0
    end

    clamp_decimal(base_success_probability.to_d + delta, 0, 1)
  end

  def adjusted_expected_hours_for(summary, base_expected_hours)
    multiplier = case summary.feasibility_label
    when "hard_to_execute" then 1.35
    when "unstable" then 1.1
    when "over_sized" then 1.2
    else 1
    end

    base_hours = base_expected_hours.to_d
    return base_hours if base_hours.zero?

    [ base_hours * multiplier, base_hours * 1.5 ].min.round(2)
  end

  def adjusted_execution_prompt_for(summary, base_prompt)
    prompt = base_prompt.to_s
    prompt = shrink_prompt_quantity(prompt, summary) if summary.feasibility_label == "over_sized"
    return prompt if prompt.include?(instruction_appendix(summary))

    [ prompt.presence, instruction_appendix(summary) ].compact.join("\n\n")
  end

  def shrink_prompt_quantity(prompt, summary)
    factor = clamp_decimal(summary.average_completion_rate.to_d, 0.5, 0.9)
    prompt.sub(QUANTITY_PATTERN) do
      original_quantity = ::Regexp.last_match(1).to_d
      unit = ::Regexp.last_match(2)
      adjusted_quantity = [ (original_quantity * factor).floor, 1 ].max
      "#{adjusted_quantity}#{unit}"
    end
  end

  def instruction_appendix(summary)
    case summary.feasibility_label
    when "easy_to_execute"
      "実行可能性補正: 過去ログ上、このタイプは完了されやすい提案です。"
    when "over_sized"
      "実行可能性補正: 過去ログ上、同種提案は完了率が低いため数量を保守化してください。"
    when "unstable"
      "実行可能性補正: 過去ログ上、変更実行が多いため、実行前に対象・除外条件・代替手順を明確にしてください。"
    when "hard_to_execute"
      "実行可能性補正: 過去ログ上、実行失敗やスキップが多いため、作業範囲を小さくし前提条件を確認してください。"
    else
      "実行可能性補正: 実行差分ログが不足しているため補正なし。"
    end
  end

  def correction_reason(summary)
    case summary.feasibility_label
    when "easy_to_execute"
      "実行可能性補正: 過去ログ上、このタイプは完了されやすいため成功確率を軽く上方補正。"
    when "over_sized"
      "実行可能性補正: 過去ログ上、同種提案は完了率が低いため数量を保守化し成功確率を下方補正。"
    when "unstable"
      "実行可能性補正: 過去ログ上、変更実行が多いため指示粒度を改善し成功確率を下方補正。"
    when "hard_to_execute"
      "実行可能性補正: 過去ログ上、実行失敗が多いため工数を増やし成功確率を下方補正。"
    else
      "実行可能性補正: 補正なし。"
    end
  end

  def append_reason(base_reason, reason)
    return reason if base_reason.blank?
    return base_reason if base_reason.include?(reason)

    [ base_reason, reason ].join("\n")
  end

  def record_no_correction(label, reason, source)
    action_candidate.metadata = action_candidate.metadata.to_h.merge(
      METADATA_KEY => {
        "applied" => false,
        "feasibility_label" => label,
        "source" => source,
        "reason" => reason
      }
    )
    Result.new(
      applied: false,
      summary: nil,
      source:,
      base_success_probability: action_candidate.success_probability,
      adjusted_success_probability: action_candidate.success_probability,
      base_expected_hours: action_candidate.expected_hours,
      adjusted_expected_hours: action_candidate.expected_hours,
      reason:
    )
  end

  def metadata_for(applied:, summary:, source:, base_values:, adjusted_success_probability:, adjusted_expected_hours:, adjusted_prompt:, reason:)
    {
      "applied" => applied,
      "source" => source,
      "feasibility_label" => summary.feasibility_label,
      "total_logs" => summary.total_logs,
      "average_completion_rate" => summary.average_completion_rate&.to_s,
      "average_variance_quantity" => summary.average_variance_quantity&.to_s,
      "base_success_probability" => base_values.fetch(:success_probability).to_s,
      "adjusted_success_probability" => adjusted_success_probability.to_s,
      "base_expected_hours" => base_values.fetch(:expected_hours).to_s,
      "adjusted_expected_hours" => adjusted_expected_hours.to_s,
      "base_execution_prompt" => base_values.fetch(:execution_prompt).to_s,
      "adjusted_execution_prompt" => adjusted_prompt.to_s,
      "base_evaluation_reason" => base_values.fetch(:evaluation_reason).to_s,
      "reason" => reason
    }
  end

  def clamp_decimal(value, minimum, maximum)
    [ [ value.to_d, minimum.to_d ].max, maximum.to_d ].min
  end
end
