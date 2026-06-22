module AicooExecutor
  class ApprovedCandidateQueuer
    Result = Data.define(:target_count, :created_count, :skipped_count, :skipped_reasons, :tasks)

    def self.queue_all!
      new(ActionCandidate.where(status: "approved")).call
    end

    def self.queue_selected!(ids)
      new(ActionCandidate.where(id: ids, status: "approved")).call
    end

    def initialize(scope)
      @scope = scope.includes(:business)
      @skipped_reasons = Hash.new(0)
      @tasks = []
    end

    def call
      target_count = scope.count

      scope.find_each do |action_candidate|
        if AicooExecutorTask.unfinished_for_action_candidate(action_candidate)
          skipped_reasons["既にExecutor登録済み"] += 1
          action_candidate.mark_executor_queued! if action_candidate.executor_queued_at.blank?
          next
        end

        tasks << TaskBuilder.from_action_candidate(action_candidate)
        action_candidate.mark_executor_queued!
      end

      Result.new(
        target_count:,
        created_count: tasks.size,
        skipped_count: target_count - tasks.size,
        skipped_reasons:,
        tasks:
      )
    end

    private

    attr_reader :scope, :skipped_reasons, :tasks
  end
end
