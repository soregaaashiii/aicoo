namespace :aicoo do
  desc "Cleanup action candidates that should not appear in the normal expected value ranking. Use APPLY=1 to update."
  task cleanup_action_expected_value_ranking: :environment do
    apply = ENV["APPLY"].to_s.in?(%w[1 true TRUE])
    stats = Hash.new(0)
    candidate_ids = []

    ActionCandidate.includes(:business).find_each do |candidate|
      stats[:checked] += 1
      cleanup = ranking_cleanup_decision(candidate)
      next unless cleanup

      stats[cleanup.fetch(:status).to_sym] += 1
      candidate_ids << candidate.id
      next unless apply

      metadata = candidate.metadata.to_h.deep_stringify_keys.merge(
        "ranking_cleanup_status" => cleanup.fetch(:status),
        "ranking_cleanup_reason" => cleanup.fetch(:reason),
        "ranking_cleanup_at" => Time.current.iso8601
      )
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
    puts "resolved=#{stats[:resolved]}"
    puts "rejected_duplicate=#{stats[:rejected_duplicate]}"
    puts "duplicates_checked=#{stats[:duplicates_checked]}"
    puts "duplicate_groups=#{stats[:duplicate_groups]}"
    puts "failed=#{stats[:failed]}"
    puts "candidate_ids=#{candidate_ids.uniq.join(',')}"
  end

  def ranking_cleanup_decision(candidate)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    return { status: "rejected_irrelevant", reason: "external_reference_or_invalid_target" } if metadata["url_classification"].to_s.in?(%w[external_reference invalid])
    return { status: "rejected_irrelevant", reason: "external_reference_or_invalid_target" } if metadata["target_url_type"].to_s.in?(%w[external_reference invalid])
    return { status: "rejected_irrelevant", reason: metadata["rejection_reason"] } if metadata["repair_reason"].present? && metadata["rejection_reason"].present?

    if daily_run_incident_candidate?(candidate) && daily_run_incident_recovered?(candidate)
      return { status: "resolved", reason: "daily_run_step_recently_succeeded" }
    end

    nil
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
    text = [
      candidate.title,
      candidate.description,
      candidate.metadata.to_h["concrete_task"],
      candidate.metadata.to_h.dig("action_plan", "summary")
    ].compact.join(" ")
    text.match?(/Daily Run|insight_generation|business_metrics_import|stuck|orphaned|partial_failed|継続停止|継続一部失敗/i)
  end

  def daily_run_incident_recovered?(candidate)
    step_name = daily_run_incident_step_name(candidate)
    return false if step_name.blank?

    recent_runs = AicooDailyRun
      .actual_runs
      .joins(:aicoo_daily_run_steps)
      .where(aicoo_daily_run_steps: { step_name: })
      .order(Arel.sql("COALESCE(aicoo_daily_runs.started_at, aicoo_daily_runs.created_at) DESC"), Arel.sql("aicoo_daily_runs.id DESC"))
      .limit(2)
    recent_runs.size >= 2 && recent_runs.all?(&:succeeded?)
  end

  def daily_run_incident_step_name(candidate)
    text = [
      candidate.title,
      candidate.description,
      candidate.metadata.to_h["step_name"],
      candidate.metadata.to_h.dig("daily_run", "step_name"),
      candidate.metadata.to_h["concrete_task"],
      candidate.metadata.to_h.dig("action_plan", "summary")
    ].compact.join(" ")
    AicooDailyRunStep::PRIMARY_STEP_NAMES.find { |step| text.include?(step) }
  end
end
