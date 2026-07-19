namespace :aicoo do
  desc "Diagnose ArticleOpportunityAnalyzer candidates for Codex / AutoRevision readiness"
  task diagnose_article_opportunity_codex: :environment do
    stats = AicooArticleOpportunityCodexTasks.diagnose
    AicooArticleOpportunityCodexTasks.print_hash(stats)
  end

  desc "Dry-run enqueue approved ArticleOpportunityAnalyzer candidates into AutoRevisionTask. Use APPLY=1 and CANDIDATE_ID or BUSINESS_ID."
  task enqueue_article_opportunity_codex: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV["APPLY"])
    stats = AicooArticleOpportunityCodexTasks.enqueue(apply:)
    AicooArticleOpportunityCodexTasks.print_hash(stats)
  end
end

module AicooArticleOpportunityCodexTasks
  module_function

  def diagnose
    stats = empty_stats.merge(mode: "diagnose")
    scope.find_each do |candidate|
      collect_candidate(stats, candidate, enqueue: false, apply: false)
    end
    stats
  end

  def enqueue(apply:)
    stats = empty_stats.merge(mode: apply ? "apply" : "dry-run", created_task_ids: [])
    unless ENV["CANDIDATE_ID"].present? || ENV["BUSINESS_ID"].present?
      stats[:blocked_count] += 1
      stats[:blocking_reasons] << "candidate_id_or_business_id_required"
      return stats
    end

    scope.where(status: "approved").find_each do |candidate|
      collect_candidate(stats, candidate, enqueue: true, apply:)
    end
    stats
  end

  def collect_candidate(stats, candidate, enqueue:, apply:)
    stats[:checked_count] += 1
    gate = Aicoo::ArticleOpportunityCodexGate.call(candidate)
    existing_task = gate.existing_task || candidate.auto_revision_tasks.where.not(status: "canceled").order(created_at: :desc).first
    increment_reason_stats(stats, gate)
    stats[:eligible_count] += 1 if gate.eligible?
    stats[:blocked_count] += 1 unless gate.eligible?
    stats[:duplicate_task_count] += 1 if existing_task
    stats[:superseded_count] += 1 unless gate.latest_snapshot

    next_action = if gate.eligible?
      enqueue ? "AutoRevisionTask作成可能" : "承認後にCodex投入可能"
    else
      gate.reasons.first || "blocked"
    end

    puts [
      "candidate_id=#{candidate.id}",
      "business_id=#{candidate.business_id}",
      "article_id=#{candidate.metadata.to_h['article_id']}",
      "article_path=#{candidate.metadata.to_h['article_path']}",
      "opportunity_type=#{candidate.metadata.to_h['opportunity_type']}",
      "production_candidate=#{candidate.metadata.to_h['production_candidate']}",
      "approved=#{candidate.status == 'approved'}",
      "latest_snapshot=#{gate.latest_snapshot}",
      "execution_brief_present=#{candidate.metadata.to_h['execution_brief'].present?}",
      "codex_eligible=#{candidate.metadata.to_h.dig('execution_brief', 'execution', 'codex_eligible') || candidate.metadata.to_h['codex_eligible']}",
      "gate_eligible=#{gate.eligible?}",
      "gate_reasons=#{gate.reasons.join('|')}",
      "risk_level=#{gate.risk_level}",
      "repository_configured=#{gate.profile&.effective_codex_repository_url.present?}",
      "execution_profile_configured=#{gate.profile.present?}",
      "existing_auto_revision_task_id=#{existing_task&.id}",
      "auto_revision_status=#{existing_task&.status}",
      "queue_eligible=#{enqueue && gate.eligible? && existing_task.blank?}",
      "next_action=#{next_action}"
    ].join(" ")

    return unless enqueue && gate.eligible? && existing_task.blank?

    if apply
      task = AutoRevisionTask.from_action_candidate(candidate, generated_by: "article_opportunity_codex_task")
      stats[:created_task_ids] << task.id if task
    end
  rescue StandardError => e
    stats[:blocked_count] += 1
    stats[:blocking_reasons] << "#{candidate.id}:#{e.class}:#{e.message}"
    warn "candidate_id=#{candidate.id} failed #{e.class}: #{e.message}"
  end

  def increment_reason_stats(stats, gate)
    stats[:human_required_count] += 1 if gate.reasons.include?("human_required")
    stats[:research_required_count] += 1 if gate.reasons.include?("research_required")
    stats[:approval_required_count] += 1 if gate.reasons.include?("not_approved")
    stats[:repository_missing_count] += 1 if gate.reasons.include?("repository_missing")
    stats[:high_risk_count] += 1 if gate.risk_level == "high"
  end

  def scope
    rows = ActionCandidate
      .includes(:business, :auto_revision_tasks)
      .where("metadata ->> 'value_model_name' = ?", Aicoo::ArticleOpportunityCodexGate::MODEL_NAME)
      .where("metadata ->> 'analysis_source' = ?", "article_analytics_snapshot")
      .where("metadata ->> 'production_candidate' = ?", "true")
      .order(:id)

    rows = rows.where(id: ENV["CANDIDATE_ID"]) if ENV["CANDIDATE_ID"].present?
    rows = rows.where(business_id: ENV["BUSINESS_ID"]) if ENV["BUSINESS_ID"].present?
    rows
  end

  def empty_stats
    {
      checked_count: 0,
      eligible_count: 0,
      blocked_count: 0,
      human_required_count: 0,
      research_required_count: 0,
      approval_required_count: 0,
      repository_missing_count: 0,
      high_risk_count: 0,
      duplicate_task_count: 0,
      superseded_count: 0,
      blocking_reasons: []
    }
  end

  def print_hash(hash)
    hash.each do |key, value|
      value = value.join(",") if value.is_a?(Array)
      puts "#{key}=#{value}"
    end
  end
end
