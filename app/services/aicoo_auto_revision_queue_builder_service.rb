class AicooAutoRevisionQueueBuilderService
  MAX_CREATED = 5
  MIN_FINAL_SCORE = 1_000.to_d
  TARGET_STATUSES = %w[idea pending approved].freeze

  Result = Data.define(:created_tasks, :skipped_count, :high_risk_candidates, :logs, :candidate_count, :skipped_reasons, :diagnostics) do
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
    diagnostics = queue_diagnostics

    self.class.candidate_scope.each do |candidate|
      candidate_count += 1
      break if created_tasks.size >= limit

      stabilize_instruction(candidate)
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
      if route.task
        created_tasks << route.task
      else
        skipped_count += 1
        skipped_reasons << {
          "candidate_id" => candidate.id,
          "business_id" => candidate.business_id,
          "title" => candidate.title,
          "final_score" => candidate.final_score.to_s,
          "reason" => "non_code_revision:#{candidate.execution_mode}"
        }
      end
      logs << route.log
    end

    Result.new(created_tasks:, skipped_count:, high_risk_candidates:, logs:, candidate_count:, skipped_reasons:, diagnostics:)
  end

  private

  attr_reader :minimum_final_score

  def skip_candidate_reason(candidate)
    return "below_minimum_final_score" if candidate.final_score.to_d < minimum_final_score
    return "active_auto_revision_task_exists" if candidate.auto_revision_tasks.any? { |task| AutoRevisionTask::ACTIVE_STATUSES.include?(task.status) }
    return "non_code_revision:#{candidate.execution_mode}" unless candidate.code_revision_execution_mode?
    return "execution_instruction_missing_file_changes" if candidate.metadata.to_h.dig("execution_instruction", "quality", "has_file_changes") == false
    return "execution_instruction_missing_completion_criteria" if candidate.metadata.to_h.dig("execution_instruction", "quality", "has_completion_criteria") == false

    nil
  end

  def stabilize_instruction(candidate)
    return if candidate.metadata.to_h.dig("execution_instruction", "version").present? &&
      candidate.execution_prompt.to_s.include?("ActionCandidate実行指示書")

    Aicoo::ActionCandidateInstructionStabilizer.call(candidate)
    candidate.reload
  rescue StandardError => e
    Rails.logger.warn("[AicooAutoRevisionQueueBuilderService] instruction stabilize failed candidate_id=#{candidate.id}: #{e.class}: #{e.message}")
  end

  def queue_diagnostics
    base_scope = ActionCandidate.active_for_ranking
    target_status_scope = base_scope.where(status: TARGET_STATUSES)
    prompt_scope = target_status_scope.where.not(execution_prompt: [ nil, "" ])
    active_task_candidate_ids = AutoRevisionTask.active.select(:action_candidate_id)

    {
      "active_candidate_count" => base_scope.count,
      "target_statuses" => TARGET_STATUSES,
      "target_status_candidate_count" => target_status_scope.count,
      "status_counts" => base_scope.group(:status).count,
      "missing_execution_prompt_count" => target_status_scope.where(execution_prompt: [ nil, "" ]).count,
      "prompt_ready_candidate_count" => prompt_scope.count,
      "below_minimum_final_score_count" => prompt_scope.where("final_score < ?", minimum_final_score).count,
      "active_auto_revision_task_exists_count" => prompt_scope.where(id: active_task_candidate_ids).count,
      "minimum_final_score" => minimum_final_score.to_s
    }
  end
end
