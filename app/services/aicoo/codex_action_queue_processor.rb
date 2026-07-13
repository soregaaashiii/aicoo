require "zlib"

module Aicoo
  class CodexActionQueueProcessor
    WAITING_STATUSES = %w[ready_for_codex queued].freeze
    ACTIVE_STATUSES = %w[sent_to_codex running].freeze
    ORDER_SQL = Arel.sql(<<~SQL.squish)
      action_candidates.final_expected_value_yen DESC NULLS LAST,
      action_candidates.success_probability DESC NULLS LAST,
      auto_revision_tasks.created_at ASC,
      auto_revision_tasks.id ASC
    SQL
    DEFAULT_INTERVAL_MINUTES = 15
    DEFAULT_MAX_STARTS_PER_HOUR = 4
    DEFAULT_MAX_STARTS_PER_DAY = 20
    DEFAULT_MAX_CONSECUTIVE_FAILURES = 3

    Result = Data.define(:started, :task, :reason, :detail)

    def initialize(force: false)
      @force = force
      @lock_acquired = false
    end

    def call
      return Result.new(started: false, task: nil, reason: "duplicate_skipped", detail: {}) unless acquire_lock

      process_with_lock
    ensure
      release_lock if @lock_acquired
    end

    private

    attr_reader :force

    def process_with_lock
      setting = AicooAutoRevisionSetting.current
      return skipped("paused", pause_reason: setting.codex_queue_pause_reason) if setting.codex_queue_paused?

      consecutive_failures = recent_consecutive_failures
      if consecutive_failures >= max_consecutive_failures
        setting.pause_codex_queue!(reason: "Codex Queueで#{consecutive_failures}件連続失敗したため一時停止しました。")
        return skipped("paused_by_consecutive_failures", consecutive_failures:)
      end

      return skipped("active_task_exists", active_task_id: active_task.id) if active_task
      return skipped("interval_not_elapsed", last_started_at:) unless force || interval_elapsed?
      return skipped("hourly_limit_reached", max_starts_per_hour:) if starts_this_hour >= max_starts_per_hour
      return skipped("daily_limit_reached", max_starts_per_day:) if starts_today >= max_starts_per_day

      task = next_task
      return skipped("no_waiting_task") unless task
      return skipped("same_business_active", business_id: task.business_id) if active_task_for_business?(task.business_id)

      detail = dispatch(task)
      status = detail["status"].to_s
      return Result.new(started: true, task:, reason: status, detail:) if status.in?(%w[created already_created])

      mark_task_failed!(task, detail)
      pause_if_failure_limit_reached!
      Result.new(started: false, task:, reason: status.presence || "failed", detail:)
    end

    def skipped(reason, detail = {})
      Result.new(started: false, task: nil, reason:, detail:)
    end

    def next_task
      AutoRevisionTask
        .joins(:action_candidate)
        .includes(:business, :action_candidate, :codex_submission)
        .where(status: WAITING_STATUSES, risk_level: "low")
        .where.not(action_candidates: { status: ActionCandidate::INACTIVE_STATUSES })
        .order(ORDER_SQL)
        .limit(50)
        .detect { |task| !blocked_by_prerequisite?(task.action_candidate) }
    end

    def active_task
      @active_task ||= AutoRevisionTask.where(status: ACTIVE_STATUSES).order(sent_to_codex_at: :asc, started_running_at: :asc, id: :asc).first
    end

    def active_task_for_business?(business_id)
      return false if business_id.blank?

      AutoRevisionTask.where(status: ACTIVE_STATUSES, business_id:).exists?
    end

    def blocked_by_prerequisite?(candidate)
      metadata = candidate.metadata.to_h
      return true if metadata["blocked"] && metadata["prerequisite_action_candidate_id"].blank?

      prerequisite_id = metadata["prerequisite_action_candidate_id"]
      return false if prerequisite_id.blank?

      prerequisite = ActionCandidate.find_by(id: prerequisite_id)
      prerequisite.blank? || !prerequisite.executed?
    end

    def dispatch(task)
      Aicoo::AutoRevisionCodexIssueDispatcher.new.call(tasks: [ task ], limit: 1).details.first.to_h
    end

    def mark_task_failed!(task, detail)
      message = [
        detail["reason"],
        detail["message"],
        Array(detail["reasons"]).join(" / ")
      ].compact_blank.join(": ").presence || "Codex Queue処理に失敗しました。"
      task.update!(status: "failed", error_message: message, finished_at: Time.current)
      task.current_execution.finish!(status: "failed", error_message: message)
    end

    def pause_if_failure_limit_reached!
      failures = recent_consecutive_failures
      return if failures < max_consecutive_failures

      AicooAutoRevisionSetting.current.pause_codex_queue!(
        reason: "Codex Queueで#{failures}件連続失敗したため一時停止しました。"
      )
    end

    def recent_consecutive_failures
      count = 0
      AutoRevisionTask.order(updated_at: :desc, id: :desc).limit(max_consecutive_failures).pluck(:status).each do |status|
        break unless status == "failed"

        count += 1
      end
      count
    end

    def interval_elapsed?
      return true unless last_started_at

      last_started_at <= interval_minutes.minutes.ago
    end

    def last_started_at
      @last_started_at ||= AutoRevisionTask.where.not(sent_to_codex_at: nil).maximum(:sent_to_codex_at)
    end

    def starts_this_hour
      AutoRevisionTask.where(sent_to_codex_at: Time.current.beginning_of_hour..Time.current).count
    end

    def starts_today
      AutoRevisionTask.where(sent_to_codex_at: Time.current.all_day).count
    end

    def interval_minutes
      env_integer("CODEX_QUEUE_INTERVAL_MINUTES", DEFAULT_INTERVAL_MINUTES)
    end

    def max_starts_per_hour
      env_integer("CODEX_MAX_STARTS_PER_HOUR", DEFAULT_MAX_STARTS_PER_HOUR)
    end

    def max_starts_per_day
      env_integer("CODEX_MAX_STARTS_PER_DAY", DEFAULT_MAX_STARTS_PER_DAY)
    end

    def max_consecutive_failures
      env_integer("CODEX_MAX_CONSECUTIVE_FAILURES", DEFAULT_MAX_CONSECUTIVE_FAILURES)
    end

    def env_integer(key, fallback)
      value = ENV[key].to_i
      value.positive? ? value : fallback
    end

    def acquire_lock
      return true unless postgresql_adapter?

      value = ActiveRecord::Base.connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
      @lock_acquired = value == true || value.to_s.in?(%w[t true 1])
    end

    def release_lock
      return unless postgresql_adapter?

      ActiveRecord::Base.connection.select_value("SELECT pg_advisory_unlock(#{lock_key})")
    ensure
      @lock_acquired = false
    end

    def postgresql_adapter?
      ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
    end

    def lock_key
      @lock_key ||= Zlib.crc32("aicoo:codex_action_queue")
    end
  end
end
