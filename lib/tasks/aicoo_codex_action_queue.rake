namespace :aicoo do
  desc "Process one waiting Codex Action queue item. Usage: bin/rails aicoo:process_codex_action_queue"
  task process_codex_action_queue: :environment do
    result = Aicoo::CodexActionQueueProcessor.new(force: ENV["FORCE"] == "1").call

    puts "AICOO Codex Action Queue"
    puts "started=#{result.started}"
    puts "reason=#{result.reason}"
    puts "task_id=#{result.task&.id}"
    puts "business_id=#{result.task&.business_id}"
    puts "detail=#{result.detail.to_json}"
  end

  desc "Diagnose Codex Action queue state. Usage: bin/rails aicoo:diagnose_codex_action_queue"
  task diagnose_codex_action_queue: :environment do
    summary = Aicoo::CodexActionQueueSummary.new.call
    duplicate_ids = AutoRevisionTask
      .where(status: AutoRevisionTask::ACTIVE_STATUSES)
      .group(:action_candidate_id)
      .having("COUNT(*) > 1")
      .count
      .keys
    blocked_count = ActionCandidate
      .where(id: AutoRevisionTask.where(status: AutoRevisionTask::ACTIVE_STATUSES).select(:action_candidate_id))
      .where("metadata ->> 'blocked' = ? OR metadata ->> 'blocked_by_prerequisite' = ?", "true", "true")
      .count
    total_unexecuted = ActionCandidate
      .active_for_ranking
      .where.not(status: %w[done rejected archived])
      .where.not(id: ActionResult.select(:action_candidate_id))
      .count

    puts "AICOO Codex Action Queue診断"
    puts "total_unexecuted=#{total_unexecuted}"
    puts "queued=#{summary.queued_count}"
    puts "ready=#{summary.ready_count}"
    puts "running=#{summary.running_count}"
    puts "sent_to_codex=#{summary.sent_count}"
    puts "completed=#{summary.completed_count}"
    puts "failed=#{summary.failed_count}"
    puts "duplicate_queue_entries=#{duplicate_ids.size}"
    puts "blocked=#{blocked_count}"
    puts "next_candidate_id=#{summary.next_task&.action_candidate_id}"
    puts "next_task_id=#{summary.next_task&.id}"
    puts "consecutive_failures=#{summary.consecutive_failures}"
    puts "paused=#{summary.paused}"
    puts "pause_reason=#{summary.pause_reason}"
    puts "candidate_ids=#{AutoRevisionTask.joins(:action_candidate).where(status: Aicoo::CodexActionQueueProcessor::WAITING_STATUSES).order(Aicoo::CodexActionQueueProcessor::ORDER_SQL).limit(20).pluck(:action_candidate_id).join(',')}"
  end

  desc "Backfill unexecuted ActionCandidates into Codex Action queue. Usage: APPLY=1 bin/rails aicoo:backfill_codex_action_queue"
  task backfill_codex_action_queue: :environment do
    apply = ENV["APPLY"] == "1"
    result = nil
    ActiveRecord::Base.transaction do
      result = AicooAutoRevisionQueueBuilderService.new(
        minimum_final_score: AicooAutoRevisionSetting.current.minimum_final_score,
        allow_medium_risk: AicooAutoRevisionSetting.current.allow_medium_risk
      ).call(limit: nil)

      unless apply
        puts "AICOO Codex Action Queue backfill dry-run"
        puts "apply=false"
        puts "candidate_count=#{result.candidate_count}"
        puts "would_create_count=#{result.created_count}"
        puts "skipped_count=#{result.skipped_count}"
        puts "candidate_ids=#{result.created_tasks.map(&:action_candidate_id).join(',')}"
        raise ActiveRecord::Rollback
      end
    end
    next unless apply

    puts "AICOO Codex Action Queue backfill"
    puts "apply=true"
    puts "candidate_count=#{result.candidate_count}"
    puts "created_count=#{result.created_count}"
    puts "skipped_count=#{result.skipped_count}"
    puts "task_ids=#{result.created_tasks.map(&:id).join(',')}"
  end
end
