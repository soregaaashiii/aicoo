module Aicoo
  class DailyRunHealthSummary
    Result = Data.define(
      :latest_run,
      :latest_status,
      :latest_started_at,
      :latest_finished_at,
      :latest_duration_seconds,
      :latest_error_summary,
      :last_success_at,
      :days_since_last_success,
      :today_run_count,
      :today_success_count,
      :today_failed_count,
      :today_partial_failed_count,
      :today_generated_action_candidates_count,
      :today_action_candidates_waiting_count,
      :today_high_score_action_candidates_count,
      :today_calibration_updated_count,
      :today_calibration_log_count,
      :today_calibration_log_counts_by_source,
      :today_pending_calibration_count,
      :danger_pending_calibration_count,
      :warning_pending_calibration_count,
      :low_confidence_pending_calibration_count,
      :failed_steps,
      :slow_steps,
      :skipped_steps,
      :step_count,
      :success_step_count,
      :failed_step_count,
      :skipped_step_count,
      :recoverable_failed_steps_count,
      :last_recovery_at,
      :recovery_failures_count,
      :health_status,
      :health_message,
      :warnings,
      :recommended_action
    )

    HIGH_SCORE_THRESHOLD = 1_000
    MANY_PENDING_THRESHOLD = 5

    def call
      Result.new(
        latest_run:,
        latest_status: latest_run&.status,
        latest_started_at: latest_run&.started_at,
        latest_finished_at: latest_run&.finished_at,
        latest_duration_seconds:,
        latest_error_summary:,
        last_success_at: last_success_run&.finished_at || last_success_run&.started_at,
        days_since_last_success:,
        today_run_count: today_runs.count,
        today_success_count: today_success_count,
        today_failed_count: today_failed_count,
        today_partial_failed_count: today_partial_failed_count,
        today_generated_action_candidates_count: today_action_candidates.count,
        today_action_candidates_waiting_count: today_action_candidates.where(status: %w[idea pending approval]).count,
        today_high_score_action_candidates_count: today_action_candidates.where("final_score >= ?", HIGH_SCORE_THRESHOLD).count,
        today_calibration_updated_count: today_runs.sum(:updated_calibration_count),
        today_calibration_log_count: today_calibration_logs.count,
        today_calibration_log_counts_by_source: calibration_log_counts_by_source,
        today_pending_calibration_count: pending_calibrations.count,
        danger_pending_calibration_count: pending_calibrations.where(warning_level: "danger").count,
        warning_pending_calibration_count: pending_calibrations.where(warning_level: "warning").count,
        low_confidence_pending_calibration_count: pending_calibrations.where(confidence_level: "low").count,
        failed_steps: failed_steps,
        slow_steps: slow_steps,
        skipped_steps: skipped_steps,
        step_count: latest_steps.count,
        success_step_count: latest_steps.select { |step| step.status == "success" }.size,
        failed_step_count: failed_steps.size,
        skipped_step_count: skipped_steps.size,
        recoverable_failed_steps_count: recoverable_failed_steps.size,
        last_recovery_at: latest_steps.filter_map(&:last_recovery_at).max,
        recovery_failures_count: latest_steps.count { |step| step.last_recovery_status == "failed" },
        health_status:,
        health_message:,
        warnings: warnings,
        recommended_action: recommended_action
      )
    end

    private

    def latest_run
      @latest_run ||= AicooDailyRun.recent.first
    end

    def today_runs
      @today_runs ||= AicooDailyRun.where(created_at: today_range)
    end

    def last_success_run
      @last_success_run ||= AicooDailyRun.successful.recent.first
    end

    def today_action_candidates
      @today_action_candidates ||= ActionCandidate.where(created_at: today_range)
    end

    def today_calibration_logs
      @today_calibration_logs ||= ActionPredictionCalibrationLog.where(calculated_at: today_range)
    end

    def pending_calibrations
      @pending_calibrations ||= ActionPredictionCalibration.where(approval_status: "pending")
    end

    def latest_steps
      @latest_steps ||= latest_run ? latest_run.aicoo_daily_run_steps.order(:started_at, :created_at).to_a : []
    end

    def failed_steps
      @failed_steps ||= latest_steps.select { |step| step.status == "failed" }
    end

    def skipped_steps
      @skipped_steps ||= latest_steps.select { |step| step.status == "skipped" }
    end

    def slow_steps
      @slow_steps ||= latest_steps.select { |step| step.slow?(average_duration:) }
    end

    def recoverable_failed_steps
      @recoverable_failed_steps ||= latest_steps.select(&:recovery_needed?)
    end

    def average_duration
      durations = latest_steps.filter_map { |step| step.duration_seconds&.to_d }.reject(&:zero?)
      return if durations.empty?

      durations.sum / durations.size
    end

    def latest_duration_seconds
      return unless latest_run&.started_at && latest_run&.finished_at

      (latest_run.finished_at - latest_run.started_at).to_i
    end

    def latest_error_summary
      [ latest_run&.error_message, latest_run&.calibration_error ].compact_blank.join(" / ").presence
    end

    def days_since_last_success
      success_at = last_success_run&.finished_at || last_success_run&.started_at
      return if success_at.blank?

      (Date.current - success_at.to_date).to_i
    end

    def today_success_count
      today_runs.where(status: AicooDailyRun::SUCCESS_STATUSES).count
    end

    def today_failed_count
      today_runs.where(status: %w[failed stuck]).count
    end

    def today_partial_failed_count
      today_runs.where(status: "partial_failed").count
    end

    def calibration_log_counts_by_source
      ActionPredictionCalibrationLog::SOURCES.index_with do |source|
        today_calibration_logs.where(source:).count
      end
    end

    def health_status
      return "critical" if critical?
      return "warning" if warning?
      return "attention" if attention?

      "healthy"
    end

    def health_message
      case health_status
      when "critical"
        "Daily Runに重大な問題があります。最優先で確認してください。"
      when "warning"
        return "#{recoverable_failed_steps.size}件の復旧可能な失敗ステップがあります。" if recoverable_failed_steps.any?

        failed_steps.any? ? "Daily Runの一部ステップが失敗しています。" : "Daily Runに一部問題があります。失敗箇所を確認してください。"
      when "attention"
        slow_steps.any? ? "Daily Runに遅いステップがあります。" : "Daily Runは動いていますが、確認すべき補正や生成状況があります。"
      else
        "Daily Runは通常運用で問題ありません。"
      end
    end

    def warnings
      [].tap do |items|
        items << "Daily Runがfailed/stuckです。" if latest_run&.status.in?(%w[failed stuck])
        items << "Daily Runがpartial_failedです。" if latest_run&.status == "partial_failed"
        items << "calibration_errorがあります。" if latest_run&.calibration_error.present?
        items << "承認待ち補正があります。" if pending_calibrations.exists?
        items << "dangerの承認待ち補正があります。" if pending_calibrations.where(warning_level: "danger").exists?
        items << "Daily Runの一部ステップが失敗しています。" if failed_steps.any?
        items << "#{recoverable_failed_steps.size}件の復旧可能な失敗ステップがあります。" if recoverable_failed_steps.any?
        items << "Daily Run step recoveryに失敗があります。" if latest_steps.any? { |step| step.last_recovery_status == "failed" }
        items << "Daily Runに遅いステップがあります。" if slow_steps.any?
        items << "今日のActionCandidate生成数が0です。" if today_action_candidates.count.zero?
        items << "今日Daily Runが未実行です。" if today_runs.count.zero?
        items << "最終成功から2日以上経過しています。" if days_since_last_success.to_i >= 2
      end
    end

    def recommended_action
      return "Daily Run詳細を確認してください" if latest_run&.status.in?(%w[failed stuck])
      return "失敗ステップを確認してください" if latest_run&.status == "partial_failed"
      return "Calibration承認待ちを確認してください" if pending_calibrations.exists?
      return "Daily Runの生成ステップを確認してください" if today_action_candidates.count.zero?

      "通常運用で問題ありません"
    end

    def critical?
      latest_run&.status.in?(%w[failed stuck]) ||
        failed_steps.any?(&:primary?) ||
        (today_success_count.zero? && today_failed_count.positive?) ||
        days_since_last_success.to_i >= 2
    end

    def warning?
      latest_run&.status == "partial_failed" ||
        latest_run&.calibration_error.present? ||
        failed_steps.any? ||
        pending_calibrations.count > MANY_PENDING_THRESHOLD ||
        today_runs.count.zero? ||
        (days_since_last_success.present? && days_since_last_success >= 1)
    end

    def attention?
      pending_calibrations.exists? ||
        pending_calibrations.where(warning_level: %w[danger warning]).exists? ||
        slow_steps.any? ||
        today_action_candidates.count.zero?
    end

    def today_range
      Date.current.all_day
    end
  end
end
