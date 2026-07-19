module Aicoo
  class ActivityLearningTrack
    Result = Data.define(:name, :action_candidate, :link_source)

    CANDIDATE_ID_KEYS = %w[action_candidate_id candidate_id].freeze

    def self.call(evaluation)
      new(evaluation).call
    end

    def initialize(evaluation)
      @evaluation = evaluation
      @activity_log = evaluation&.business_activity_log
    end

    def call
      candidate = candidate_from_explicit_id
      return Result.new(name: "action_candidate", action_candidate: candidate, link_source: "explicit_candidate_id") if candidate

      candidate = candidate_from_execution_log
      return Result.new(name: "action_candidate", action_candidate: candidate, link_source: "action_execution_log") if candidate

      Result.new(name: "independent_activity", action_candidate: nil, link_source: nil)
    end

    private

    attr_reader :evaluation, :activity_log

    def candidate_from_explicit_id
      explicit_candidate_ids.each do |id|
        candidate = ActionCandidate.find_by(id:)
        return candidate if candidate
      end
      nil
    end

    def explicit_candidate_ids
      payloads.flat_map do |payload|
        nested_candidate = payload["action_candidate"].is_a?(Hash) ? payload["action_candidate"] : {}
        CANDIDATE_ID_KEYS.filter_map { |key| payload[key].presence } +
          CANDIDATE_ID_KEYS.filter_map { |key| nested_candidate[key].presence }
      end.uniq.select { |id| numeric_id?(id) }
    end

    def payloads
      [
        activity_log&.metadata,
        activity_log&.before_snapshot,
        activity_log&.after_snapshot,
        evaluation&.metadata
      ].map { |payload| payload.to_h.deep_stringify_keys }
    end

    def candidate_from_execution_log
      log_id = [
        activity_log&.metadata.to_h["action_execution_log_id"],
        activity_log&.after_snapshot.to_h["action_execution_log_id"],
        evaluation&.metadata.to_h.dig("activity_learning_pipeline", "action_execution_log_id")
      ].find { |id| numeric_id?(id) }
      return unless log_id

      ActionExecutionLog.find_by(id: log_id)&.action_candidate
    end

    def numeric_id?(value)
      value.to_s.match?(/\A\d+\z/)
    end
  end
end
