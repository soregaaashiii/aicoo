class AicooLearningLoopAutoLinkService
  AUTO_LINK_METHOD = "nearest_action_execution_log".freeze

  def initialize(action_result)
    @action_result = action_result
  end

  def call
    return nil unless action_result&.persisted? && action_result.action_candidate_id.present?

    log = best_unlinked_execution_log
    return nil unless log

    log.update!(
      action_result:,
      metadata: log.metadata.to_h.merge(auto_link_metadata)
    )
    log
  end

  private

  attr_reader :action_result

  def best_unlinked_execution_log
    candidates = ActionExecutionLog.where(
      action_candidate_id: action_result.action_candidate_id,
      action_result_id: nil
    ).to_a
    return candidates.first if candidates.one?
    return nil if candidates.empty?

    ranked = candidates.map { |log| [ distance_from_action_result(log), log ] }
                       .sort_by { |distance, log| [ distance, -log.created_at.to_i ] }
    return nil if ranked.size > 1 && ranked.first.first == ranked.second.first

    ranked.first.second
  end

  def distance_from_action_result(log)
    log_time = log.finished_at || log.started_at || log.created_at
    return Float::INFINITY unless log_time

    (log_time.to_time - action_result.executed_on.to_time).abs
  end

  def auto_link_metadata
    {
      "auto_linked_action_result_id" => action_result.id,
      "auto_linked_at" => Time.current.iso8601,
      "auto_link_method" => AUTO_LINK_METHOD
    }
  end
end
