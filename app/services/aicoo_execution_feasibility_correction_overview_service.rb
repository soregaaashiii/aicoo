class AicooExecutionFeasibilityCorrectionOverviewService
  METADATA_KEY = AicooExecutionFeasibilityCorrectionService::METADATA_KEY
  LABELS = %w[
    over_sized
    unstable
    hard_to_execute
    easy_to_execute
    mostly_executable
    insufficient_data
  ].freeze

  Summary = Data.define(
    :key,
    :label,
    :total_candidates,
    :corrected_count,
    :correction_rate,
    :labels_count,
    :average_success_probability_delta,
    :average_expected_hours_delta,
    :top_correction_reasons,
    :insight_text
  )

  def initialize(scope: ActionCandidate.includes(:business).all)
    @scope = scope
  end

  def call
    candidates = scope.to_a
    {
      overall: summarize("overall", "全体", candidates),
      by_action_type: summarize_groups(group_by_action_type(candidates)),
      by_business: summarize_groups(group_by_business(candidates)),
      by_business_action_type: summarize_groups(group_by_business_action_type(candidates)),
      recent_corrected: recent_corrected(candidates)
    }
  end

  private

  attr_reader :scope

  def summarize_groups(groups)
    groups.map { |key, data| summarize(key, data.fetch(:label), data.fetch(:candidates)) }
          .sort_by { |summary| [ -summary.correction_rate.to_d, -summary.corrected_count, summary.label ] }
  end

  def group_by_action_type(candidates)
    candidates.group_by { |candidate| candidate.action_type.presence || "unknown" }
              .transform_values { |items| { label: items.first.action_type.presence || "unknown", candidates: items } }
  end

  def group_by_business(candidates)
    candidates.group_by(&:business_id).transform_values do |items|
      { label: items.first.business&.name.presence || "Business ##{items.first.business_id}", candidates: items }
    end
  end

  def group_by_business_action_type(candidates)
    candidates.group_by { |candidate| [ candidate.business_id, candidate.action_type.presence || "unknown" ] }
              .transform_values do |items|
                business_name = items.first.business&.name.presence || "Business ##{items.first.business_id}"
                action_type = items.first.action_type.presence || "unknown"
                { label: "#{business_name} / #{action_type}", candidates: items }
              end
  end

  def summarize(key, label, candidates)
    candidates = Array(candidates)
    metadata_list = candidates.map { |candidate| correction_metadata(candidate) }
    corrected_metadata = metadata_list.select { |metadata| metadata["applied"] == true }
    labels_count = label_counts(metadata_list)
    success_deltas = corrected_metadata.filter_map { |metadata| delta(metadata, "success_probability") }
    hour_deltas = corrected_metadata.filter_map { |metadata| delta(metadata, "expected_hours") }

    Summary.new(
      key:,
      label:,
      total_candidates: candidates.size,
      corrected_count: corrected_metadata.size,
      correction_rate: ratio(corrected_metadata.size, candidates.size),
      labels_count:,
      average_success_probability_delta: average(success_deltas),
      average_expected_hours_delta: average(hour_deltas),
      top_correction_reasons: top_reasons(corrected_metadata),
      insight_text: insight_text(label, labels_count, corrected_metadata.size, candidates.size)
    )
  end

  def label_counts(metadata_list)
    counts = metadata_list.each_with_object(Hash.new(0)) do |metadata, result|
      label = metadata["feasibility_label"].presence || "insufficient_data"
      result[label] += 1 if LABELS.include?(label)
    end
    LABELS.index_with { |label| counts.fetch(label, 0) }
  end

  def delta(metadata, key)
    base = metadata["base_#{key}"]
    adjusted = metadata["adjusted_#{key}"]
    return if base.blank? || adjusted.blank?

    adjusted.to_d - base.to_d
  end

  def average(values)
    values = values.compact
    return nil if values.empty?

    values.sum(&:to_d) / values.size
  end

  def ratio(numerator, denominator)
    return 0.to_d if denominator.to_i.zero?

    numerator.to_d / denominator.to_d
  end

  def top_reasons(metadata_list)
    metadata_list.filter_map { |metadata| metadata["reason"].presence }
                 .tally
                 .sort_by { |_reason, count| -count }
                 .first(3)
                 .map { |reason, count| "#{reason}（#{count}件）" }
  end

  def insight_text(label, labels_count, corrected_count, total_candidates)
    return "補正対象の候補はまだありません。" if total_candidates.zero?
    return "#{label} は補正率が低く、現時点では大きな実行負荷の偏りは見えていません。" if corrected_count.zero?

    if labels_count.fetch("hard_to_execute").positive?
      "#{label} は実行失敗が多く、候補粒度を小さくする必要があります。"
    elsif labels_count.fetch("over_sized").positive?
      "#{label} は過去ログ上、数量が大きくなりやすいため補正率が高いです。"
    elsif labels_count.fetch("unstable").positive?
      "#{label} は変更実行が多く、execution_promptの具体化が必要です。"
    elsif labels_count.fetch("easy_to_execute").positive?
      "#{label} は完了されやすく、同種提案を増やせる可能性があります。"
    else
      "#{label} は実行可能性補正が入っています。補正理由を確認してください。"
    end
  end

  def recent_corrected(candidates)
    candidates.select { |candidate| correction_metadata(candidate)["applied"] == true }
              .sort_by(&:updated_at)
              .reverse
              .first(10)
  end

  def correction_metadata(candidate)
    candidate.metadata.to_h.fetch(METADATA_KEY, {})
  end
end
