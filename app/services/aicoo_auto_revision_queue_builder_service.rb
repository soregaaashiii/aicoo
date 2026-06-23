class AicooAutoRevisionQueueBuilderService
  MAX_CREATED = 5
  MIN_FINAL_SCORE = 1_000.to_d
  TARGET_STATUSES = %w[idea pending approved].freeze

  Result = Data.define(:created_tasks, :skipped_count, :high_risk_candidates) do
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
    @allowed_risk_levels = allow_medium_risk ? %w[low medium] : %w[low]
  end

  def call(limit: MAX_CREATED)
    created_tasks = []
    skipped_count = 0
    high_risk_candidates = []

    self.class.candidate_scope.each do |candidate|
      break if created_tasks.size >= limit

      if skip_candidate?(candidate)
        skipped_count += 1
        next
      end

      risk_level = AutoRevisionTask.risk_level_for(candidate)
      unless allowed_risk_levels.include?(risk_level)
        high_risk_candidates << candidate if risk_level == "high"
        skipped_count += 1
        next
      end

      created_tasks << AutoRevisionTask.from_action_candidate(candidate, generated_by: "auto_queue")
    end

    Result.new(created_tasks:, skipped_count:, high_risk_candidates:)
  end

  private

  attr_reader :minimum_final_score, :allowed_risk_levels

  def skip_candidate?(candidate)
    candidate.final_score.to_d < minimum_final_score ||
      candidate.auto_revision_tasks.any? { |task| AutoRevisionTask::ACTIVE_STATUSES.include?(task.status) }
  end
end
