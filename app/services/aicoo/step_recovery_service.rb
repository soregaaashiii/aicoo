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
      step = recovery_step
      return skipped_result(started_at, "#{step_name} step は再実行不可です") unless recoverable?
      return guarded_result(started_at, step.recovery_unavailable_reason) unless step.recovery_available?

      lock_recovery!(step)
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
    ensure
      unlock_recovery!(step) if @lock_acquired && step
    end

    private

    attr_reader :daily_run, :step_name

    def recoverable?
      AicooDailyRunStep::RECOVERABLE_STEP_NAMES.include?(step_name)
    end

    def latest_step
      @latest_step ||= daily_run.aicoo_daily_run_steps.where(step_name:).recent.first
    end

    def recovery_step
      latest_step || daily_run.aicoo_daily_run_steps.create!(step_name:, status: "skipped")
    end

    def perform_recovery!
      case step_name
      when "calibration"
        recover_calibration
      when "article_opportunity_analysis"
        recover_article_opportunity_analysis
      when "business_metrics_import"
        recover_business_metrics_import
      when "owner_task_digest"
        Aicoo::OwnerTaskDigest.new.call
        "Owner Task Digest step recovery completed successfully"
      when "action_result_evaluation"
        results = ActionResultEvaluator.evaluate_pending!
        "ActionResult evaluation step recovery completed successfully count=#{results.size}"
      when "score_snapshot"
        result = ActionCandidateScoreSnapshotter.new.snapshot_top_candidates!(date: daily_run.target_date)
        "Score snapshot step recovery completed successfully count=#{result.created_count}"
      when "source_app_diff_detection"
        result = Aicoo::SourceAppDiffDetector.new.call
        "Source app diff detection step recovery completed successfully created=#{result.created_count} skipped=#{result.skipped_count} errors=#{result.error_count}"
      when "activity_log_evaluation_queue_build"
        trigger_result = Aicoo::ActivityEvaluationTrigger.call(invoked_by: "Manual")
        result = trigger_result.builder_result
        raise trigger_result.exception if result.nil? && trigger_result.exception.present?

        "Activity evaluation queue step recovery completed successfully created=#{result.created_count} evaluated=#{result.evaluated_count} invoked=#{trigger_result.builder_invoked_count}"
      when "data_preparation_queue"
        result = DataPreparationExecutorQueuer.new.call
        daily_run.update!(
          data_preparation_candidates_count: result.candidate_count,
          data_preparation_auto_queued_count: result.queued_count
        )
        "Data preparation queue step recovery completed successfully candidates=#{result.candidate_count} queued=#{result.queued_count}"
      when "meta_evaluation_snapshot"
        result = MetaEvaluationSnapshotter.new.snapshot!(date: daily_run.target_date, aicoo_daily_run: daily_run)
        "Meta evaluation snapshot step recovery completed successfully created=#{result.created_count}"
      when "owner_execution_queue"
        result = Aicoo::OwnerExecutionQueueBuilder.new(due_on: Date.current, generated_from: "daily_run_recovery").call
        "Owner execution queue step recovery completed successfully created=#{result.created.size} skipped=#{result.skipped.size}"
      when "business_playbook_update"
        result = Aicoo::BusinessPlaybookBuilder.update_all!(collect_records: false)
        "Business playbook step recovery completed successfully updated=#{result.updated_count}"
      when "traffic_channel_recording"
        result = Aicoo::TrafficChannels::DailyRecorder.record!(daily_run:)
        "Traffic channel recording step recovery completed successfully recorded=#{result.recorded_count} skipped=#{result.skipped_count}"
      when "system_mode_snapshot"
        snapshot = Aicoo::SystemModeSnapshotBuilder.new.call
        "System mode snapshot step recovery completed successfully id=#{snapshot.id}"
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

    def recover_business_metrics_import
      results = BusinessMetricDailyImporter.import_all!(date: daily_run.target_date)
      daily_run.update!(business_metrics_imported_count: results.size)
      "BusinessMetricDaily import step recovery completed successfully count=#{results.size}"
    end

    def recover_article_opportunity_analysis
      business = Aicoo::ArticleOpportunityDailyRun.target_businesses.first
      return "Article opportunity analysis recovery skipped reason=target_business_not_found" unless business

      result = Aicoo::ArticleOpportunityDailyRun.call(daily_run:, business:)
      raise(result.errors.first.presence || "Article opportunity analysis failed") if result.status == "failed"

      metadata = recovery_step.metadata.to_h.merge(Aicoo::ArticleOpportunityDailyRun.metadata_for(result))
      recovery_step.update!(metadata:)
      "Article opportunity analysis step recovery completed status=#{result.status} candidates_created=#{result.candidate_created_count} promoted=#{result.proposal_promoted_count} today_eligible=#{result.today_eligible_count}"
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

    def guarded_result(started_at, message)
      finished_at = Time.current
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
      step = recovery_step
      step.update!(
        recovery_attempt_count: step.recovery_attempt_count + 1,
        last_recovery_at: finished_at,
        last_recovery_status: status,
        last_recovery_message: message
      )
    end

    def lock_recovery!(step)
      step.update!(recovery_locked: true, recovery_locked_at: Time.current)
      @lock_acquired = true
    end

    def unlock_recovery!(step)
      step.update!(recovery_locked: false)
      @lock_acquired = false
    end

    def duration_seconds(started_at, finished_at)
      finished_at - started_at
    end
  end
end
