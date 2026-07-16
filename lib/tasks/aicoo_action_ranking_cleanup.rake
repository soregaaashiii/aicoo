namespace :aicoo do
  desc "Cleanup action candidates that should not appear in the normal expected value ranking. Use APPLY=1 to update."
  task cleanup_action_expected_value_ranking: :environment do
    apply = ENV["APPLY"].to_s.in?(%w[1 true TRUE])
    stats = Hash.new(0)
    candidate_ids = []
    daily_run_debug_rows = []
    title_like_daily_run_debug_rows = []

    ActionCandidate.includes(:business).find_each do |candidate|
      stats[:checked] += 1
      title_like_daily_run_debug_rows << daily_run_candidate_debug_row(candidate) if title_like_daily_run_issue?(candidate)
      if already_rejected_irrelevant?(candidate)
        stats[:skipped_already_rejected_irrelevant] += 1
        next
      end
      if already_resolved_daily_run_incident?(candidate)
        stats[:skipped_already_resolved_daily_run] += 1
        next
      end

      cleanup = ranking_cleanup_decision(candidate, stats:, daily_run_debug_rows:)
      next unless cleanup

      stats[cleanup.fetch(:status).to_sym] += 1
      candidate_ids << candidate.id
      stats[:resolved_candidate_ids] = stats_array(stats, :resolved_candidate_ids) + [ candidate.id ] if cleanup.fetch(:status) == "resolved"
      next unless apply

      metadata = candidate.metadata.to_h.deep_stringify_keys.merge(
        "ranking_cleanup_status" => cleanup.fetch(:status),
        "ranking_cleanup_reason" => cleanup.fetch(:reason),
        "ranking_cleanup_at" => Time.current.iso8601
      )
      metadata.merge!(cleanup.fetch(:daily_run_normalization, {})) if cleanup[:daily_run_normalization]
      metadata["daily_run_recovery_diagnosis"] = cleanup[:daily_run_diagnosis] if cleanup[:daily_run_diagnosis]
      metadata["representative_action_candidate_id"] = cleanup[:representative_id] if cleanup[:representative_id]
      candidate.update_columns(status: cleanup.fetch(:status), metadata:, updated_at: Time.current)
    rescue StandardError => e
      stats[:failed] += 1
      Rails.logger.warn("[aicoo:cleanup_action_expected_value_ranking] action_candidate_id=#{candidate&.id} failed: #{e.class}: #{e.message}")
    end

    duplicate_stats = cleanup_duplicate_action_candidates(apply:)
    stats.merge!(duplicate_stats) { |_key, left, right| left.to_i + right.to_i }

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{stats[:checked]}"
    puts "rejected_irrelevant=#{stats[:rejected_irrelevant]}"
    puts "skipped_already_rejected_irrelevant=#{stats[:skipped_already_rejected_irrelevant]}"
    puts "resolved=#{stats[:resolved]}"
    puts "daily_run_candidates_checked=#{stats[:daily_run_candidates_checked]}"
    puts "daily_run_latest_success_found=#{stats[:daily_run_latest_success_found]}"
    puts "daily_run_still_failing=#{stats[:daily_run_still_failing]}"
    puts "skipped_already_resolved_daily_run=#{stats[:skipped_already_resolved_daily_run]}"
    puts "rejected_duplicate=#{stats[:rejected_duplicate]}"
    puts "duplicates_checked=#{stats[:duplicates_checked]}"
    puts "duplicate_groups=#{stats[:duplicate_groups]}"
    puts "failed=#{stats[:failed]}"
    puts "resolved_candidate_ids=#{Array(stats[:resolved_candidate_ids]).uniq.join(',')}"
    puts "unresolved_daily_run_candidate_ids=#{Array(stats[:unresolved_daily_run_candidate_ids]).uniq.join(',')}"
    title_like_daily_run_debug_rows.uniq { |row| row.fetch(:id) }.each do |row|
      puts "title_like_daily_run_candidate_id=#{row.fetch(:id)} title=#{row.fetch(:title).inspect} action_type=#{row.fetch(:action_type)} department=#{row.fetch(:department)} step_name=#{row.fetch(:step_name)} generation_source=#{row.fetch(:generation_source)}"
    end
    daily_run_debug_rows.each do |row|
      puts "daily_run_candidate_id=#{row.fetch(:id)} title=#{row.fetch(:title).inspect} action_type=#{row.fetch(:action_type)} department=#{row.fetch(:department)} step_name=#{row.fetch(:step_name)} generation_source=#{row.fetch(:generation_source)}"
    end
    puts "candidate_ids=#{candidate_ids.uniq.join(',')}"
  end

  def ranking_cleanup_decision(candidate, stats:, daily_run_debug_rows:)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    return { status: "rejected_irrelevant", reason: "external_reference_or_invalid_target" } if metadata["url_classification"].to_s.in?(%w[external_reference invalid])
    return { status: "rejected_irrelevant", reason: "external_reference_or_invalid_target" } if metadata["target_url_type"].to_s.in?(%w[external_reference invalid])
    return { status: "rejected_irrelevant", reason: metadata["rejection_reason"] } if metadata["repair_reason"].present? && metadata["rejection_reason"].present?

    if daily_run_incident_candidate?(candidate)
      stats[:daily_run_candidates_checked] += 1
      daily_run_debug_rows << daily_run_candidate_debug_row(candidate)
      diagnosis = daily_run_incident_recovery_diagnosis(candidate)
      if diagnosis.fetch(:recovered)
        stats[:daily_run_latest_success_found] += 1
        return {
          status: "resolved",
          reason: "daily_run_step_recently_succeeded",
          daily_run_diagnosis: diagnosis,
          daily_run_normalization: daily_run_incident_normalization(candidate, diagnosis)
        }
      end

      stats[:daily_run_still_failing] += 1
      stats[:unresolved_daily_run_candidate_ids] = stats_array(stats, :unresolved_daily_run_candidate_ids) + [ candidate.id ]
    end

    nil
  end

  def already_rejected_irrelevant?(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    return true if metadata["ranking_cleanup_status"].to_s == "rejected_irrelevant" && candidate.status.to_s == "rejected_irrelevant"
    return false unless candidate.status.to_s == "rejected"
    return false unless metadata["url_classification"].to_s.in?(%w[external_reference invalid]) ||
      metadata["target_url_type"].to_s.in?(%w[external_reference invalid])
    return false unless metadata["repair_reason"].present?
    return false unless metadata["rejection_reason"].present?

    metadata.dig("target_url_repair", "after_status").to_s == "rejected"
  end

  def stats_array(stats, key)
    value = stats[key]
    value.is_a?(Array) ? value : []
  end

  def already_resolved_daily_run_incident?(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    candidate.status.to_s == "resolved" &&
      metadata["ranking_cleanup_status"].to_s == "resolved" &&
      metadata["ranking_cleanup_reason"].to_s == "daily_run_step_recently_succeeded"
  end

  def daily_run_incident_recovered?(candidate)
    daily_run_incident_recovery_diagnosis(candidate).fetch(:recovered)
  end

  def daily_run_incident_recovery_diagnosis(candidate)
    step_name = daily_run_incident_step_name(candidate)
    return { recovered: false, reason: "step_name_missing" } if step_name.blank?

    latest_success_step = latest_successful_daily_run_step(step_name)
    return { recovered: true, reason: "latest_step_success", step_name:, latest_success_step_id: latest_success_step.id } if latest_success_step && latest_success_after_candidate?(latest_success_step, candidate)

    recent_steps = recent_daily_run_steps(step_name, limit: 2)
    if recent_steps.size >= 2 && recent_steps.all? { |step| step.status == "success" } && recent_steps.first && latest_success_after_candidate?(recent_steps.first, candidate)
      return {
        recovered: true,
        reason: "recent_two_steps_success",
        step_name:,
        recent_success_step_ids: recent_steps.map(&:id)
      }
    end

    {
      recovered: false,
      reason: "recent_step_success_not_found",
      step_name:,
      recent_step_statuses: recent_steps.map { |step| "#{step.id}:#{step.status}" }
    }
  end

  def cleanup_duplicate_action_candidates(apply:)
    stats = Hash.new(0)
    groups = ActionCandidate
      .active_for_ranking
      .includes(:business)
      .to_a
      .group_by { |candidate| action_candidate_cleanup_dedupe_key(candidate) }
      .select { |_key, candidates| candidates.size > 1 }
    stats[:duplicates_checked] = groups.values.sum(&:size)
    stats[:duplicate_groups] = groups.size

    groups.each_value do |candidates|
      representative = candidates.max_by { |candidate| [ candidate.expected_profit_yen.to_i, candidate.updated_at.to_i, candidate.id ] }
      duplicates = candidates - [ representative ]
      source_ids = candidates.map(&:id)
      source_values = candidates.to_h { |candidate| [ candidate.id, candidate.expected_profit_yen.to_i ] }

      if apply
        rep_metadata = representative.metadata.to_h.deep_stringify_keys.merge(
          "evidence_sources" => candidates.flat_map { |candidate| Array(candidate.metadata.to_h["evidence_sources"]) + [ candidate.generation_source ] }.compact_blank.uniq,
          "source_candidate_ids" => source_ids,
          "source_expected_values" => source_values,
          "grouped_opportunity_count" => candidates.size,
          "ranking_cleanup_at" => Time.current.iso8601
        )
        representative.update_columns(metadata: rep_metadata, updated_at: Time.current)
      end

      duplicates.each do |duplicate|
        stats[:rejected_duplicate] += 1
        next unless apply

        metadata = duplicate.metadata.to_h.deep_stringify_keys.merge(
          "ranking_cleanup_status" => "rejected_duplicate",
          "ranking_cleanup_reason" => "duplicate_action_candidate",
          "representative_action_candidate_id" => representative.id,
          "source_candidate_ids" => source_ids,
          "source_expected_values" => source_values,
          "ranking_cleanup_at" => Time.current.iso8601
        )
        duplicate.update_columns(status: "rejected_duplicate", metadata:, updated_at: Time.current)
      end
    end

    stats
  end

  def action_candidate_cleanup_dedupe_key(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    [
      candidate.business_id,
      cleanup_normalized_action_type(candidate.action_type),
      cleanup_normalize(
        metadata["target_keyword"].presence ||
          metadata["target_query"].presence ||
          metadata["source_query"].presence ||
          metadata["query"].presence ||
          metadata["search_query"].presence ||
          metadata.dig("evidence", "query").presence ||
          candidate.title
      ),
      cleanup_normalize(metadata["planned_url"].presence || metadata["proposed_url"].presence || metadata["recommended_url"].presence || metadata["recommended_slug"].presence),
      cleanup_normalize(metadata["content_type"].presence || metadata["work_type"].presence || candidate.action_type)
    ].join("::")
  end

  def cleanup_normalized_action_type(action_type)
    action_type.to_s.in?(%w[new_article_candidate article_create seo_article]) ? "article_create" : action_type.to_s
  end

  def cleanup_normalize(value)
    value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]　]+/, " ").strip
  end

  def daily_run_incident_candidate?(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    return true if metadata["source_type"].to_s == "daily_run_issue"
    return true if metadata["task_type"].to_s.in?(%w[daily_run_failure daily_run_partial_failed daily_run_incident])
    return true if metadata["daily_run_incident"].is_a?(Hash) && metadata.dig("daily_run_incident", "step_name").present?
    return true if metadata["daily_run"].is_a?(Hash) && metadata.dig("daily_run", "step_name").present?
    return true if metadata["latest_run_id"].present? && daily_run_incident_step_name(candidate).present?
    return true if candidate.action_type.to_s.in?(%w[daily_run_failure daily_run_incident system_recovery])
    return true if candidate.department.to_s.downcase.in?(%w[daily_run daily-run system]) && daily_run_incident_step_name(candidate).present?
    return true if title_like_daily_run_issue?(candidate) && daily_run_incident_step_name(candidate).present?

    text = [
      candidate.title,
      metadata["concrete_task"],
      metadata.dig("action_plan", "summary")
    ].compact.join(" ").strip
    daily_run_issue_text?(text)
  end

  def title_like_daily_run_issue?(candidate)
    candidate.title.to_s.strip.match?(/\ADaily\s*Runが/i)
  end

  def daily_run_issue_text?(text)
    steps = AicooDailyRunStep::PRIMARY_STEP_NAMES.join("|")
    text.match?(/\ADaily\s*Runが\s*(#{steps})\s*で\s*継続(?:停止|一部失敗)/i) ||
      text.match?(/\ADaily\s*Run\s*(#{steps})\s*(?:stuck|failed|orphaned|partial_failed)/i) ||
      text.match?(/\A(#{steps})\s*継続(?:停止|一部失敗)/i) ||
      text.match?(/\A(#{steps})\s*(?:stuck|failed|orphaned|partial_failed)/i)
  end

  def daily_run_candidate_debug_row(candidate)
    {
      id: candidate.id,
      title: candidate.title.to_s,
      action_type: candidate.action_type.to_s,
      department: candidate.department.to_s,
      step_name: daily_run_incident_step_name(candidate).to_s,
      generation_source: candidate.generation_source.to_s
    }
  end

  def daily_run_incident_step_name(candidate)
    text = [
      candidate.title,
      candidate.description,
      candidate.metadata.to_h["step_name"],
      candidate.metadata.to_h.dig("daily_run", "step_name"),
      candidate.metadata.to_h.dig("daily_run_incident", "step_name"),
      candidate.metadata.to_h.dig("incident", "step_name"),
      candidate.metadata.to_h["last_step"],
      candidate.metadata.to_h["concrete_task"],
      candidate.metadata.to_h.dig("action_plan", "summary"),
      candidate.metadata.to_h.dig("action_plan", "target"),
      candidate.metadata.to_h["root_cause"]
    ].compact.join(" ").strip
    AicooDailyRunStep::PRIMARY_STEP_NAMES.find { |step| text.include?(step) }
  end

  def daily_run_incident_normalization(candidate, diagnosis)
    step_name = diagnosis[:step_name].presence || daily_run_incident_step_name(candidate)
    latest_step = step_name.present? ? latest_successful_daily_run_step(step_name) : nil
    {
      "source_type" => "daily_run_issue",
      "incident_type" => daily_run_incident_type(candidate),
      "step_name" => step_name,
      "latest_run_id" => latest_step&.aicoo_daily_run_id,
      "daily_run_incident" => candidate.metadata.to_h.deep_stringify_keys.fetch("daily_run_incident", {}).merge(
        "step_name" => step_name,
        "incident_type" => daily_run_incident_type(candidate),
        "latest_run_id" => latest_step&.aicoo_daily_run_id,
        "normalized_at" => Time.current.iso8601
      ).compact
    }.compact
  end

  def daily_run_incident_type(candidate)
    text = [
      candidate.title,
      candidate.description,
      candidate.metadata.to_h["incident_type"],
      candidate.metadata.to_h.dig("daily_run_incident", "incident_type")
    ].compact.join(" ")
    return "partial_failed" if text.match?(/一部失敗|partial_failed/i)
    return "orphaned" if text.match?(/orphan/i)
    return "failed" if text.match?(/failed|失敗/i)

    "stuck"
  end

  def latest_successful_daily_run_step(step_name)
    AicooDailyRunStep
      .successful
      .joins(:aicoo_daily_run)
      .merge(AicooDailyRun.actual_runs)
      .where(step_name:)
      .order(Arel.sql("COALESCE(aicoo_daily_run_steps.finished_at, aicoo_daily_run_steps.updated_at, aicoo_daily_run_steps.created_at) DESC"), id: :desc)
      .first
  end

  def recent_daily_run_steps(step_name, limit:)
    AicooDailyRunStep
      .joins(:aicoo_daily_run)
      .merge(AicooDailyRun.actual_runs)
      .where(step_name:)
      .order(Arel.sql("COALESCE(aicoo_daily_run_steps.finished_at, aicoo_daily_run_steps.updated_at, aicoo_daily_run_steps.created_at) DESC"), id: :desc)
      .limit(limit)
      .to_a
  end

  def latest_success_after_candidate?(step, candidate)
    success_at = step.finished_at || step.updated_at || step.created_at
    incident_at = daily_run_incident_time(candidate)
    return true if incident_at.blank?

    success_at.present? && success_at >= incident_at
  end

  def daily_run_incident_time(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    [
      metadata["incident_started_at"],
      metadata["failed_at"],
      metadata["stuck_at"],
      metadata.dig("daily_run", "started_at"),
      metadata.dig("daily_run_incident", "started_at"),
    ].compact_blank.filter_map do |value|
      value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? value : Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end.min
  end
end
