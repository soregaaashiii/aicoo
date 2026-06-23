class AicooExecutionFeasibilityInsightService
  Summary = Data.define(
    :key,
    :label,
    :total_logs,
    :completed_count,
    :partial_count,
    :over_completed_count,
    :changed_count,
    :failed_count,
    :skipped_count,
    :average_completion_rate,
    :average_variance_quantity,
    :completion_rate_score,
    :feasibility_label,
    :recommendation
  )

  MINIMUM_LOGS = 3

  def initialize(scope: ActionExecutionLog.includes(:action_candidate, :business).all)
    @scope = scope
  end

  def call
    {
      overall: summarize("overall", "全体", scope),
      by_business_action_type: summarize_groups(group_by_business_action_type),
      by_action_type: summarize_groups(group_by_action_type),
      by_business: summarize_groups(group_by_business)
    }
  end

  private

  attr_reader :scope

  def summarize_groups(groups)
    groups.map { |key, data| summarize(key, data.fetch(:label), data.fetch(:logs)) }
          .sort_by { |summary| [ summary.feasibility_label == "insufficient_data" ? 1 : 0, -summary.total_logs ] }
  end

  def group_by_action_type
    scope.group_by { |log| log.action_candidate&.action_type.presence || "unknown" }
         .transform_values { |logs| { label: logs.first.action_candidate&.action_type.presence || "unknown", logs: } }
  end

  def group_by_business_action_type
    scope.group_by { |log| [ log.business_id, log.action_candidate&.action_type.presence || "unknown" ] }
         .transform_values do |logs|
           action_type = logs.first.action_candidate&.action_type.presence || "unknown"
           business_name = logs.first.business&.name.presence || "Business ##{logs.first.business_id}"
           { label: "#{business_name} / #{action_type}", logs: }
         end
  end

  def group_by_business
    scope.group_by(&:business_id).transform_values do |logs|
      { label: logs.first.business&.name.presence || "Business ##{logs.first.business_id}", logs: }
    end
  end

  def summarize(key, label, logs)
    logs = Array(logs)
    counts = status_counts(logs)
    average_completion_rate = average(logs.filter_map(&:completion_rate))
    average_variance_quantity = average(logs.filter_map(&:variance_quantity))
    feasibility_label = feasibility_label_for(
      total_logs: logs.size,
      average_completion_rate:,
      counts:
    )

    Summary.new(
      key:,
      label:,
      total_logs: logs.size,
      completed_count: counts.fetch("completed"),
      partial_count: counts.fetch("partial"),
      over_completed_count: counts.fetch("over_completed"),
      changed_count: counts.fetch("changed"),
      failed_count: counts.fetch("failed"),
      skipped_count: counts.fetch("skipped"),
      average_completion_rate:,
      average_variance_quantity:,
      completion_rate_score: completion_rate_score(average_completion_rate),
      feasibility_label:,
      recommendation: recommendation_for(feasibility_label)
    )
  end

  def status_counts(logs)
    counts = logs.group_by(&:status).transform_values(&:size)
    ActionExecutionLog::STATUSES.index_with { |status| counts.fetch(status, 0) }
  end

  def average(values)
    values = values.compact
    return nil if values.empty?

    values.sum(&:to_d) / values.size
  end

  def completion_rate_score(average_completion_rate)
    return 0 if average_completion_rate.blank?

    [ (average_completion_rate.to_d * 100).round, 100 ].min
  end

  def feasibility_label_for(total_logs:, average_completion_rate:, counts:)
    return "insufficient_data" if total_logs < MINIMUM_LOGS

    failed_or_skipped = counts.fetch("failed") + counts.fetch("skipped")
    changed_ratio = counts.fetch("changed").to_d / total_logs
    failed_ratio = failed_or_skipped.to_d / total_logs
    completion_rate = average_completion_rate.to_d

    return "hard_to_execute" if failed_ratio >= 0.34
    return "unstable" if changed_ratio >= 0.34
    return "over_sized" if completion_rate < 0.6
    return "easy_to_execute" if completion_rate >= 1.0 && failed_ratio < 0.2
    return "mostly_executable" if completion_rate >= 0.8

    "over_sized"
  end

  def recommendation_for(feasibility_label)
    case feasibility_label
    when "easy_to_execute"
      "このタイプは実行されやすいため、同種の提案を増やせます。"
    when "mostly_executable"
      "概ね実行可能です。execution_promptを少し具体化すると安定します。"
    when "over_sized"
      "planned_quantityを小さくし、分割提案にしてください。必要ならexpected_hoursを増やします。"
    when "unstable"
      "別方法で実行されやすいため、execution_promptに判断基準と代替手順を追加してください。"
    when "hard_to_execute"
      "failed/skippedが多いため、success_probabilityを少し下げ、実行前提を見直してください。"
    else
      "ActionExecutionLogを3件以上記録すると判定できます。"
    end
  end
end
