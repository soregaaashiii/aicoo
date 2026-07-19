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
      break if limit.present? && created_tasks.size >= limit

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
    if Aicoo::ArticleOpportunityCodexGate.article_opportunity_candidate?(candidate)
      gate = Aicoo::ArticleOpportunityCodexGate.call(candidate)
      return "article_opportunity_gate:#{gate.reasons.join('|')}" unless gate.eligible?
    end

    return "below_minimum_final_score" if candidate.final_score.to_d < minimum_final_score
    return "active_auto_revision_task_exists" if candidate.auto_revision_tasks.any? { |task| AutoRevisionTask::ACTIVE_STATUSES.include?(task.status) }
    return "non_code_revision:#{candidate.execution_mode}" unless candidate.code_revision_execution_mode?
    return "execution_readiness:#{execution_readiness(candidate).readiness}" unless execution_readiness(candidate).ready?
    return "ranking_guard:#{ranking_guard_reason}" if (ranking_guard_reason = Aicoo::ActionCandidateRankingGuard.rejection_reason(candidate)).present?
    return "target_unresolved_for_codex" if target_unresolved_for_codex?(candidate)
    return "blocked_by_prerequisite" if prerequisite_blocked?(candidate)
    return "execution_instruction_missing_file_changes" if candidate.metadata.to_h.dig("execution_instruction", "quality", "has_file_changes") == false
    return "execution_instruction_missing_completion_criteria" if candidate.metadata.to_h.dig("execution_instruction", "quality", "has_completion_criteria") == false

    nil
  end

  def execution_readiness(candidate)
    @execution_readiness ||= {}
    @execution_readiness[candidate.id] ||= Aicoo::ActionCandidateExecutionReadiness.call(candidate)
  end

  def target_unresolved_for_codex?(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    return false unless unresolved_target_text?(candidate, metadata)

    codex_target_fields(candidate, metadata).all?(&:blank?)
  end

  def unresolved_target_text?(candidate, metadata)
    text = [
      candidate.title,
      candidate.description,
      candidate.evaluation_reason,
      candidate.execution_prompt,
      metadata["target_url_warning"],
      metadata["owner_next_step"],
      metadata["concrete_task"],
      metadata.dig("action_plan", "summary"),
      metadata.dig("action_plan", "target")
    ].compact.join(" ")

    text.match?(/対象未特定|対象ページ未特定|滞在時間が短いページ|競合が強いキーワード|導線|CV|CTA/)
  end

  def codex_target_fields(candidate, metadata)
    [
      metadata["target_url"],
      metadata["target_url_or_identifier"],
      metadata["page_path"],
      metadata["owned_target_url"],
      metadata["target_file"],
      metadata["target_files"],
      metadata["target_metrics"],
      metadata.dig("action_plan", "target_url"),
      metadata.dig("action_plan", "target_file"),
      metadata.dig("action_plan", "target_files")
    ].flatten.compact_blank
  end

  def prerequisite_blocked?(candidate)
    metadata = candidate.metadata.to_h
    return true if metadata["blocked"] && metadata["prerequisite_action_candidate_id"].blank?

    prerequisite_id = metadata["prerequisite_action_candidate_id"]
    return false if prerequisite_id.blank?

    prerequisite = ActionCandidate.find_by(id: prerequisite_id)
    prerequisite.blank? || !prerequisite.executed?
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
