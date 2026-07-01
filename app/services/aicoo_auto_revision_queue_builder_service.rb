class AicooAutoRevisionQueueBuilderService
  MAX_CREATED = 5
  MIN_FINAL_SCORE = 1_000.to_d
  TARGET_STATUSES = %w[idea pending approved].freeze

  Result = Data.define(:created_tasks, :skipped_count, :high_risk_candidates, :logs, :candidate_count, :skipped_reasons) do
    def created_count
      created_tasks.size
    end
  end

  def self.candidate_scope
    ActionCandidate.includes(:business, :auto_revision_tasks)
                   .active_for_ranking
                   .where(status: TARGET_STATUSES)
                   .where.not(execution_prompt: [ nil, "" ])
                   .order(final_score: :desc, created_at: :desc)
  end

  def initialize(minimum_final_score: MIN_FINAL_SCORE, allow_medium_risk: true)
    @minimum_final_score = minimum_final_score.to_d
    @allow_medium_risk = allow_medium_risk
  end

  def call(limit: MAX_CREATED)
    created_tasks = []
    skipped_count = 0
    high_risk_candidates = []
    logs = []
    skipped_reasons = []
    candidate_count = 0

    self.class.candidate_scope.each do |candidate|
      candidate_count += 1
      break if created_tasks.size >= limit

      if (reason = skip_candidate_reason(candidate))
        skipped_count += 1
        skipped_reasons << {
          "candidate_id" => candidate.id,
          "business_id" => candidate.business_id,
          "title" => candidate.title,
          "final_score" => candidate.final_score.to_s,
          "reason" => reason
        }
        next
      end

      risk_level = AutoRevisionTask.risk_level_for(candidate)
      high_risk_candidates << candidate if risk_level == "high"

      route = Aicoo::BusinessAutoRevisionRouter.new(candidate, generated_by: "auto_queue").call
      created_tasks << route.task
      logs << route.log
    end

    Result.new(created_tasks:, skipped_count:, high_risk_candidates:, logs:, candidate_count:, skipped_reasons:)
  end

  private

  attr_reader :minimum_final_score

  def skip_candidate_reason(candidate)
    return "below_minimum_final_score" if candidate.final_score.to_d < minimum_final_score
    return "active_auto_revision_task_exists" if candidate.auto_revision_tasks.any? { |task| AutoRevisionTask::ACTIVE_STATUSES.include?(task.status) }

    nil
  end
end
