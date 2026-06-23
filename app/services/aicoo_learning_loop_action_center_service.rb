class AicooLearningLoopActionCenterService
  INACTIVE_STATUSES = %w[archived rejected].freeze

  ActionItem = Data.define(:action_candidate, :business, :quick_action_label, :quick_action_path, :detail_path) do
    def title
      action_candidate.title
    end

    def final_score
      action_candidate.final_score
    end

    def expected_value_yen
      action_candidate.final_expected_value_yen.to_i.positive? ? action_candidate.final_expected_value_yen : action_candidate.expected_total_value_yen
    end
  end

  Summary = Data.define(
    :candidates_missing_execution_logs,
    :candidates_missing_action_results,
    :candidates_missing_revenue_events,
    :execution_log_backlog_count,
    :action_result_backlog_count,
    :revenue_event_backlog_count
  ) do
    def empty?
      execution_log_backlog_count.zero? && action_result_backlog_count.zero? && revenue_event_backlog_count.zero?
    end
  end

  def initialize(candidate_scope: ActionCandidate.includes(:business).all, limit: 5)
    @candidate_scope = candidate_scope
    @limit = limit
  end

  def call
    candidates = prioritized_candidates
    candidate_ids = candidates.map(&:id)
    execution_logs = ActionExecutionLog.where(action_candidate_id: candidate_ids).to_a
    action_results = ActionResult.where(action_candidate_id: candidate_ids).to_a
    candidates_with_execution_logs = execution_logs.map(&:action_candidate_id).uniq
    candidates_with_action_results = action_results.map(&:action_candidate_id).uniq
    candidates_with_revenue_events = candidate_ids_with_linked_revenue_events(candidate_ids, action_results, execution_logs)

    missing_execution_logs = candidates.reject { |candidate| candidates_with_execution_logs.include?(candidate.id) }
    missing_action_results = candidates.select { |candidate| candidates_with_execution_logs.include?(candidate.id) }
                                       .reject { |candidate| candidates_with_action_results.include?(candidate.id) }
    missing_revenue_events = candidates.select { |candidate| candidates_with_action_results.include?(candidate.id) }
                                       .reject { |candidate| candidates_with_revenue_events.include?(candidate.id) }

    Summary.new(
      candidates_missing_execution_logs: items_for(missing_execution_logs, :execution_log),
      candidates_missing_action_results: items_for(missing_action_results, :action_result),
      candidates_missing_revenue_events: items_for(missing_revenue_events, :revenue_event),
      execution_log_backlog_count: missing_execution_logs.size,
      action_result_backlog_count: missing_action_results.size,
      revenue_event_backlog_count: missing_revenue_events.size
    )
  end

  private

  attr_reader :candidate_scope, :limit

  def prioritized_candidates
    candidate_scope.where.not(status: INACTIVE_STATUSES).to_a.sort_by do |candidate|
      [
        -(candidate.final_score || 0).to_d,
        -expected_value_for(candidate).to_d,
        -candidate.created_at.to_i
      ]
    end
  end

  def items_for(candidates, kind)
    candidates.first(limit).map do |candidate|
      ActionItem.new(
        action_candidate: candidate,
        business: candidate.business,
        quick_action_label: quick_action_label_for(kind),
        quick_action_path: quick_action_path_for(candidate, kind),
        detail_path: Rails.application.routes.url_helpers.action_candidate_path(candidate)
      )
    end
  end

  def candidate_ids_with_linked_revenue_events(candidate_ids, action_results, execution_logs)
    direct_ids = RevenueEvent.where(action_candidate_id: candidate_ids).distinct.pluck(:action_candidate_id)

    result_candidate_ids = if action_results.any?
      result_id_to_candidate_id = action_results.index_by(&:id).transform_values(&:action_candidate_id)
      RevenueEvent.where(action_result_id: result_id_to_candidate_id.keys)
                  .distinct
                  .pluck(:action_result_id)
                  .filter_map { |result_id| result_id_to_candidate_id[result_id] }
    else
      []
    end

    log_candidate_ids = if execution_logs.any?
      log_id_to_candidate_id = execution_logs.index_by(&:id).transform_values(&:action_candidate_id)
      RevenueEvent.where(action_execution_log_id: log_id_to_candidate_id.keys)
                  .distinct
                  .pluck(:action_execution_log_id)
                  .filter_map { |log_id| log_id_to_candidate_id[log_id] }
    else
      []
    end

    (direct_ids + result_candidate_ids + log_candidate_ids).compact.uniq
  end

  def quick_action_label_for(kind)
    case kind
    when :execution_log
      "実行差分を記録"
    when :action_result
      "結果を登録"
    else
      "売上を登録"
    end
  end

  def quick_action_path_for(candidate, kind)
    routes = Rails.application.routes.url_helpers

    case kind
    when :execution_log
      routes.new_action_execution_log_path(action_candidate_id: candidate.id)
    when :action_result
      routes.new_action_result_path(action_candidate_id: candidate.id)
    else
      routes.new_revenue_event_path(revenue_event: { business_id: candidate.business_id })
    end
  end

  def expected_value_for(candidate)
    [
      candidate.final_expected_value_yen,
      candidate.expected_total_value_yen,
      candidate.expected_profit_yen
    ].compact.max || 0
  end
end
