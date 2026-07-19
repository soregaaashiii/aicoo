namespace :aicoo do
  desc "Diagnose execution_brief quality for ArticleOpportunityAnalyzer candidates"
  task diagnose_article_opportunity_execution_briefs: :environment do
    stats = AicooArticleOpportunityExecutionBriefTasks.diagnose
    AicooArticleOpportunityExecutionBriefTasks.print_hash(stats)
  end

  desc "Backfill execution_brief for ArticleOpportunityAnalyzer candidates. Dry-run by default; use APPLY=1 to save."
  task backfill_article_opportunity_execution_briefs: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV["APPLY"])
    stats = AicooArticleOpportunityExecutionBriefTasks.backfill(apply:)
    AicooArticleOpportunityExecutionBriefTasks.print_hash(stats)
  end
end

module AicooArticleOpportunityExecutionBriefTasks
  module_function

  def diagnose
    stats = {
      mode: "diagnose",
      checked_count: 0,
      valid_count: 0,
      incomplete_count: 0,
      codex_eligible_count: 0,
      human_required_count: 0,
      research_required_count: 0,
      invalid_target_count: 0,
      candidate_ids: []
    }

    scope.find_each do |candidate|
      stats[:checked_count] += 1
      metadata = candidate.metadata.to_h
      brief = metadata["execution_brief"].to_h
      validation = validate_brief(brief)

      stats[:valid_count] += 1 if validation[:valid]
      stats[:incomplete_count] += 1 unless validation[:valid]
      stats[:codex_eligible_count] += 1 if brief.dig("execution", "codex_eligible")
      stats[:human_required_count] += 1 if brief.dig("execution", "human_required")
      stats[:research_required_count] += 1 if brief.dig("execution", "research_required")
      stats[:invalid_target_count] += 1 if brief.dig("target", "target_type").to_s.in?(%w[article_not_found invalid_target])
      stats[:candidate_ids] << candidate.id unless validation[:valid]

      puts [
        "candidate_id=#{candidate.id}",
        "status=#{candidate.status}",
        "article_id=#{metadata['article_id']}",
        "article_path=#{metadata['article_path']}",
        "improvement_type=#{metadata['opportunity_type']}",
        "title=#{candidate.title}",
        "execution_brief_present=#{brief.present?}",
        "target_valid=#{validation[:target_valid]}",
        "evidence_complete=#{validation[:evidence_complete]}",
        "recommended_changes_count=#{Array(brief['recommended_changes']).size}",
        "completion_conditions_count=#{Array(brief['completion_conditions']).size}",
        "codex_eligible=#{brief.dig('execution', 'codex_eligible')}",
        "human_required=#{brief.dig('execution', 'human_required')}",
        "research_required=#{brief.dig('execution', 'research_required')}",
        "missing_information=#{Array(brief['missing_information']).join('|')}",
        "invalid_internal_links=#{validation[:invalid_internal_links].join('|')}",
        "factual_risk=#{brief.dig('safety', 'factual_risk')}",
        "next_action=#{brief.dig('execution', 'suggested_next_action')}"
      ].join(" ")
    end

    stats
  end

  def backfill(apply:)
    stats = {
      mode: apply ? "apply" : "dry-run",
      checked_count: 0,
      eligible_count: 0,
      updated_count: 0,
      unchanged_count: 0,
      skipped_terminal_status: 0,
      skipped_missing_snapshot: 0,
      skipped_old_snapshot: 0,
      failed_count: 0,
      candidate_ids: []
    }

    scope.find_each do |candidate|
      stats[:checked_count] += 1
      if candidate.status.to_s.in?(terminal_statuses)
        stats[:skipped_terminal_status] += 1
        next
      end

      metadata = candidate.metadata.to_h
      snapshot = AicooDataSnapshot.find_by(id: metadata["snapshot_id"])
      unless snapshot
        stats[:skipped_missing_snapshot] += 1
        next
      end
      unless latest_snapshot?(candidate, snapshot)
        stats[:skipped_old_snapshot] += 1
        next
      end

      stats[:eligible_count] += 1
      payload = snapshot.payload.to_h.deep_stringify_keys
      opportunity = opportunity_from(metadata)
      breakdown = metadata["score_breakdown"].to_h
      score = metadata["opportunity_score"] || metadata["total_score"] || 0
      brief = Aicoo::ArticleOpportunityExecutionBriefBuilder.call(
        business: candidate.business,
        snapshot:,
        payload:,
        opportunity:,
        score:,
        breakdown:
      )
      new_metadata = metadata.merge(brief.metadata)
      changed = candidate.title != brief.title ||
        candidate.description != brief.description ||
        candidate.execution_prompt != brief.execution_prompt ||
        metadata["execution_brief"] != new_metadata["execution_brief"]

      if changed
        stats[:updated_count] += 1
        stats[:candidate_ids] << candidate.id
        candidate.update!(title: brief.title, description: brief.description, execution_prompt: brief.execution_prompt, metadata: new_metadata) if apply
      else
        stats[:unchanged_count] += 1
      end

      puts [
        "candidate_id=#{candidate.id}",
        "status=#{candidate.status}",
        "mode=#{stats[:mode]}",
        "changed=#{changed}",
        "opportunity_type=#{metadata['opportunity_type']}",
        "title=#{brief.title}",
        "codex_eligible=#{brief.metadata['codex_eligible']}",
        "execution_readiness=#{brief.metadata['execution_readiness']}"
      ].join(" ")
    rescue StandardError => e
      stats[:failed_count] += 1
      stats[:candidate_ids] << candidate.id
      warn "candidate_id=#{candidate.id} failed #{e.class}: #{e.message}"
    end

    stats
  end

  def scope
    ActionCandidate
      .where("metadata ->> 'value_model_name' = ?", model_name)
      .where("metadata ->> 'analysis_source' = ?", "article_analytics_snapshot")
      .order(:id)
  end

  def model_name
    Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME
  end

  def terminal_statuses
    ActionCandidate::INACTIVE_STATUSES
  end

  def opportunity_from(metadata)
    {
      "opportunity_type" => metadata["opportunity_type"],
      "label" => metadata["opportunity_label"],
      "next_action" => metadata["next_action"],
      "score" => metadata["opportunity_score_component"],
      "search_demand_score" => metadata["search_demand_score"],
      "improvement_potential_score" => metadata["improvement_potential_score"],
      "expected_improvement_score" => metadata["expected_improvement_score"],
      "success_probability" => metadata["success_probability"],
      "estimated_work_hours" => metadata["estimated_work_hours"],
      "business_value" => metadata["business_value"],
      "ranking_reason" => metadata["ranking_reason"]
    }
  end

  def latest_snapshot?(candidate, snapshot)
    payload = snapshot.payload.to_h.deep_stringify_keys
    article_id = payload["article_id"].presence || candidate.metadata.to_h["article_id"]
    return false if article_id.blank?

    latest = AicooDataSnapshot
      .where(source_type: "article_analytics")
      .order(captured_at: :desc, id: :desc)
      .detect do |row|
        row_payload = row.payload.to_h.deep_stringify_keys
        next false unless row_payload["business_id"].to_i == candidate.business_id
        next false unless row_payload["article_id"].to_s == article_id.to_s
        next false if row_payload["snapshot_status"].to_s.in?(%w[archived ignored])

        true
      end

    latest&.id == snapshot.id
  end

  def validate_brief(brief)
    changes = Array(brief["recommended_changes"])
    conditions = Array(brief["completion_conditions"])
    target = brief["target"].to_h
    evidence = brief["evidence"].to_h
    invalid_links = changes.flat_map do |change|
      Array(change.dig("evidence", "candidate_links")).filter_map do |link|
        path = link.to_h["path"].to_s
        url = link.to_h["url"].to_s
        path.start_with?("/articles/") && url.start_with?("https://suelog.jp/articles/") ? nil : (url.presence || path)
      end
    end
    target_valid = target["target_type"].present? && target["article_id"].present?
    evidence_complete = evidence.present? && evidence["analyzer"].present?
    valid = brief.present? && target_valid && evidence_complete && changes.any? && conditions.any? && invalid_links.empty?

    {
      valid:,
      target_valid:,
      evidence_complete:,
      invalid_internal_links: invalid_links
    }
  end

  def print_hash(hash)
    hash.each do |key, value|
      value = value.join(",") if value.is_a?(Array)
      puts "#{key}=#{value}"
    end
  end
end
