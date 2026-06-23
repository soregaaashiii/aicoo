class AicooLearningLoopSummaryService
  METADATA_KEY = AicooExecutionFeasibilityCorrectionService::METADATA_KEY
  LEARNING_STATE_LABELS = %w[
    not_started
    collecting_execution_data
    collecting_result_data
    correction_active
    learning_loop_active
  ].freeze

  Summary = Data.define(
    :total_candidates,
    :candidates_with_execution_logs,
    :execution_log_coverage_rate,
    :total_execution_logs,
    :candidates_with_action_results,
    :result_coverage_rate,
    :candidates_with_revenue_events,
    :revenue_event_coverage_rate,
    :corrected_candidates_count,
    :correction_rate,
    :average_completion_rate,
    :average_success_probability_delta,
    :average_expected_hours_delta,
    :recent_learning_events,
    :learning_state_label,
    :next_missing_item
  )

  LearningEvent = Data.define(:occurred_at, :event_type, :label, :path)

  def initialize(
    candidate_scope: ActionCandidate.includes(:business).all,
    execution_log_scope: ActionExecutionLog.includes(:action_candidate, :business).all,
    action_result_scope: ActionResult.includes(:action_candidate, :business).all,
    revenue_event_scope: RevenueEvent.all
  )
    @candidate_scope = candidate_scope
    @execution_log_scope = execution_log_scope
    @action_result_scope = action_result_scope
    @revenue_event_scope = revenue_event_scope
  end

  def call
    candidates = candidate_scope.to_a
    total_candidates = candidates.size
    execution_candidate_ids = execution_log_scope.distinct.pluck(:action_candidate_id)
    action_results = action_result_scope.to_a
    execution_logs = execution_log_scope.to_a
    result_candidate_ids = action_results.map(&:action_candidate_id).uniq
    revenue_candidate_ids = candidate_ids_with_linked_revenue_events(candidate_ids(candidates), action_results, execution_logs)
    corrected_candidates = candidates.select { |candidate| correction_metadata(candidate)["applied"] == true }
    success_deltas = corrected_candidates.filter_map { |candidate| correction_delta(candidate, "success_probability") }
    hour_deltas = corrected_candidates.filter_map { |candidate| correction_delta(candidate, "expected_hours") }

    attributes = {
      total_candidates:,
      candidates_with_execution_logs: (candidate_ids(candidates) & execution_candidate_ids).size,
      execution_log_coverage_rate: ratio((candidate_ids(candidates) & execution_candidate_ids).size, total_candidates),
      total_execution_logs: execution_log_scope.count,
      candidates_with_action_results: (candidate_ids(candidates) & result_candidate_ids).size,
      result_coverage_rate: ratio((candidate_ids(candidates) & result_candidate_ids).size, total_candidates),
      candidates_with_revenue_events: (candidate_ids(candidates) & revenue_candidate_ids).size,
      revenue_event_coverage_rate: ratio((candidate_ids(candidates) & revenue_candidate_ids).size, total_candidates),
      corrected_candidates_count: corrected_candidates.size,
      correction_rate: ratio(corrected_candidates.size, total_candidates),
      average_completion_rate: average(execution_log_scope.filter_map(&:completion_rate)),
      average_success_probability_delta: average(success_deltas),
      average_expected_hours_delta: average(hour_deltas),
      recent_learning_events: recent_learning_events,
      learning_state_label: nil,
      next_missing_item: nil
    }

    learning_state_label = learning_state_for(attributes)
    Summary.new(**attributes.merge(
      learning_state_label:,
      next_missing_item: next_missing_item_for(learning_state_label, attributes)
    ))
  end

  private

  attr_reader :candidate_scope, :execution_log_scope, :action_result_scope, :revenue_event_scope

  def candidate_ids(candidates)
    candidates.filter_map(&:id)
  end

  def candidate_ids_with_linked_revenue_events(action_candidate_ids, action_results, execution_logs)
    direct_ids = revenue_event_scope.where(action_candidate_id: action_candidate_ids).distinct.pluck(:action_candidate_id)
    result_ids = action_results.map(&:id)
    log_ids = execution_logs.map(&:id)

    result_candidate_ids = if result_ids.any?
      result_id_to_candidate_id = action_results.index_by(&:id).transform_values(&:action_candidate_id)
      revenue_event_scope.where(action_result_id: result_ids).distinct.pluck(:action_result_id).filter_map do |result_id|
        result_id_to_candidate_id[result_id]
      end
    else
      []
    end

    log_candidate_ids = if log_ids.any?
      log_id_to_candidate_id = execution_logs.index_by(&:id).transform_values(&:action_candidate_id)
      revenue_event_scope.where(action_execution_log_id: log_ids).distinct.pluck(:action_execution_log_id).filter_map do |log_id|
        log_id_to_candidate_id[log_id]
      end
    else
      []
    end

    (direct_ids + result_candidate_ids + log_candidate_ids).compact.uniq
  end

  def learning_state_for(attributes)
    return "not_started" if attributes.fetch(:total_execution_logs).zero?
    return "collecting_execution_data" if attributes.fetch(:candidates_with_action_results) < 3
    return "collecting_result_data" if attributes.fetch(:corrected_candidates_count).zero?
    return "learning_loop_active" if attributes.fetch(:total_execution_logs) >= 10 &&
                                    attributes.fetch(:candidates_with_action_results) >= 5 &&
                                    attributes.fetch(:corrected_candidates_count) >= 3 &&
                                    attributes.fetch(:candidates_with_revenue_events).positive?

    "correction_active"
  end

  def next_missing_item_for(label, attributes)
    case label
    when "not_started"
      "実行ログをもっと登録してください。"
    when "collecting_execution_data"
      "ActionResultを登録してください。"
    when "collecting_result_data"
      "実行可能性補正が動くまでActionExecutionLogを蓄積してください。"
    when "correction_active"
      return "RevenueEventを登録してください。" if attributes.fetch(:candidates_with_revenue_events).zero?

      "補正データは十分に集まり始めています。"
    else
      "学習ループは回り始めています。次は補正結果の精度を確認してください。"
    end
  end

  def recent_learning_events
    events = []
    events.concat(recent_execution_events)
    events.concat(recent_result_events)
    events.concat(recent_correction_events)
    events.sort_by(&:occurred_at).reverse.first(8)
  end

  def recent_execution_events
    execution_log_scope.order(created_at: :desc).limit(5).map do |log|
      LearningEvent.new(
        occurred_at: log.created_at,
        event_type: "execution_log",
        label: "#{log.business.name}: 実行差分を記録（#{log.status}）",
        path: Rails.application.routes.url_helpers.action_execution_log_path(log)
      )
    end
  end

  def recent_result_events
    action_result_scope.order(created_at: :desc).limit(5).map do |result|
      LearningEvent.new(
        occurred_at: result.created_at,
        event_type: "action_result",
        label: "#{result.business.name}: ActionResultを記録（#{result.evaluation_status}）",
        path: Rails.application.routes.url_helpers.action_result_path(result)
      )
    end
  end

  def recent_correction_events
    candidate_scope.select { |candidate| correction_metadata(candidate)["applied"] == true }
                   .sort_by(&:updated_at)
                   .reverse
                   .first(5)
                   .map do |candidate|
      metadata = correction_metadata(candidate)
      LearningEvent.new(
        occurred_at: candidate.updated_at,
        event_type: "feasibility_correction",
        label: "#{candidate.business.name}: 実行可能性補正（#{metadata["feasibility_label"]}）",
        path: Rails.application.routes.url_helpers.action_candidate_path(candidate)
      )
    end
  end

  def correction_delta(candidate, key)
    metadata = correction_metadata(candidate)
    base = metadata["base_#{key}"]
    adjusted = metadata["adjusted_#{key}"]
    return if base.blank? || adjusted.blank?

    adjusted.to_d - base.to_d
  end

  def correction_metadata(candidate)
    candidate.metadata.to_h.fetch(METADATA_KEY, {})
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
end
