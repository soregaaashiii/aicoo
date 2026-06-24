module Aicoo
  class StepRecoveryService
    Result = Data.define(:success, :message, :started_at, :finished_at, :duration_seconds, :error_message)

    def self.run!(daily_run:, step_name:)
      new(daily_run:, step_name:).run!
    end

    def initialize(daily_run:, step_name:)
      @daily_run = daily_run
      @step_name = step_name.to_s
    end

    def run!
      started_at = Time.current
      return skipped_result(started_at, "#{step_name} step は再実行不可です") unless recoverable?

      result_message = perform_recovery!
      finished_at = Time.current
      update_step!("success", result_message, finished_at)
      Result.new(
        success: true,
        message: result_message,
        started_at:,
        finished_at:,
        duration_seconds: duration_seconds(started_at, finished_at),
        error_message: nil
      )
    rescue StandardError => e
      finished_at = Time.current
      error_message = "#{e.class}: #{e.message}"
      update_step!("failed", error_message, finished_at)
      Result.new(
        success: false,
        message: nil,
        started_at:,
        finished_at:,
        duration_seconds: duration_seconds(started_at, finished_at),
        error_message:
      )
    end

    private

    attr_reader :daily_run, :step_name

    def recoverable?
      AicooDailyRunStep::RECOVERABLE_STEP_NAMES.include?(step_name)
    end

    def latest_step
      @latest_step ||= daily_run.aicoo_daily_run_steps.where(step_name:).recent.first
    end

    def perform_recovery!
      case step_name
      when "calibration"
        recover_calibration
      when "owner_task_digest"
        Aicoo::OwnerTaskDigest.new.call
        "Owner Task Digest step recovery completed successfully"
      when "action_result_evaluation"
        results = ActionResultEvaluator.evaluate_pending!
        "ActionResult evaluation step recovery completed successfully count=#{results.size}"
      when "score_snapshot"
        result = ActionCandidateScoreSnapshotter.new.snapshot_top_candidates!(date: daily_run.target_date)
        "Score snapshot step recovery completed successfully count=#{result.created_count}"
      end
    end

    def recover_calibration
      result = Aicoo::CalibrationEngine.run!(source: "step_recovery", aicoo_daily_run: daily_run)
      daily_run.update!(
        calibration_ran: true,
        calibration_started_at: Time.current,
        calibration_finished_at: Time.current,
        calibration_error: nil,
        updated_calibration_count: result.calibration_count,
        calibration_log_count: result.logs.size,
        pending_calibration_count: result.pending_count
      )
      "Calibration step recovery completed successfully updated=#{result.calibration_count} logs=#{result.logs.size}"
    end

    def skipped_result(started_at, message)
      finished_at = Time.current
      update_step!("skipped", message, finished_at)
      Result.new(
        success: false,
        message:,
        started_at:,
        finished_at:,
        duration_seconds: duration_seconds(started_at, finished_at),
        error_message: nil
      )
    end

    def update_step!(status, message, finished_at)
      step = latest_step || daily_run.aicoo_daily_run_steps.create!(step_name:, status: "skipped")
      step.update!(
        recovery_attempt_count: step.recovery_attempt_count + 1,
        last_recovery_at: finished_at,
        last_recovery_status: status,
        last_recovery_message: message
      )
    end

    def duration_seconds(started_at, finished_at)
      finished_at - started_at
    end
  end
end
