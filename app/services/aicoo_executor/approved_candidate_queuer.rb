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
        if AutoRevisionTask.active.exists?(action_candidate:)
          skipped_reasons["既にAutoRevisionTaskへ統合済み"] += 1
          next
        end

        tasks << AutoRevisionTask.from_action_candidate(action_candidate, generated_by: "approved_candidate_queuer")
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
