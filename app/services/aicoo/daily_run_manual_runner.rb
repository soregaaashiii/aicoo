module Aicoo
  class DailyRunManualRunner
    Result = Data.define(
      :mode,
      :target_date,
      :source,
      :daily_run,
      :retry_limit_bypassed,
      :blocking_reason,
      :selected_steps,
      :executed_steps,
      :skipped_steps,
      :success,
      :message
    )

    StepResult = Data.define(:step_name, :status, :message, :error_message)

    def self.call(target_date: nil, target_step: nil, apply: false, requested_by: "render_shell")
      new(target_date:, target_step:, apply:, requested_by:).call
    end

    def initialize(target_date: nil, target_step: nil, apply: false, requested_by: "render_shell")
      @target_date = target_date || AicooDailyRunSetting.current.target_date
      @target_step = target_step.to_s.presence
      @apply = apply
      @requested_by = requested_by
    end

    def call
      diagnostic = Aicoo::DailyRunRetryDiagnostic.call(target_date:)
      return blocked_result(diagnostic, "同じ対象日のDaily Runが現在実行中です") if diagnostic.active_running_run
      return blocked_result(diagnostic, "対象日のDaily Runが見つかりません") unless diagnostic.latest_run

      selected_steps = select_steps(diagnostic)
      return blocked_result(diagnostic, "回復対象Stepがありません") if selected_steps.blank?

      return dry_run_result(diagnostic, selected_steps) unless apply?

      executed = []
      skipped = []
      run = diagnostic.latest_run
      run.with_lock do
        active = Aicoo::DailyRunStuckGuard.active_running_run_for(target_date)
        return blocked_result(diagnostic, "同じ対象日のDaily Runが現在実行中です") if active

        selected_steps.each do |step|
          if step.persisted? && !step.recoverable?
            skipped << StepResult.new(step.step_name, "skipped", "recoverableではありません", nil)
            next
          end

          persisted_step = step.persisted? ? step : run.aicoo_daily_run_steps.create!(step_name: step.step_name, status: "skipped")
          record_manual_bypass!(run, persisted_step)
          result = Aicoo::StepRecoveryService.run!(daily_run: run, step_name: persisted_step.step_name)
          executed << StepResult.new(
            persisted_step.step_name,
            result.success ? "success" : "failed",
            result.message,
            result.error_message
          )
        end
      end

      Result.new(
        mode: "apply",
        target_date:,
        source: "manual",
        daily_run: run.reload,
        retry_limit_bypassed: diagnostic.retry_limit_reached || diagnostic.blocking_reason == "step_retry_limit_reached",
        blocking_reason: diagnostic.blocking_reason,
        selected_steps: selected_steps.map(&:step_name),
        executed_steps: executed,
        skipped_steps: skipped,
        success: executed.any? && executed.all? { |row| row.status == "success" },
        message: executed.map { |row| "#{row.step_name}:#{row.status}" }.join(", ")
      )
    end

    private

    attr_reader :target_date, :target_step, :requested_by

    def apply?
      @apply
    end

    def select_steps(diagnostic)
      candidates = diagnostic.recoverable_steps
      candidates = candidates.select { |step| step.step_name == target_step } if target_step.present?
      return candidates if candidates.any?
      return [] unless target_step.present?
      return [] unless AicooDailyRunStep::RECOVERABLE_STEP_NAMES.include?(target_step)

      [ diagnostic.latest_run.aicoo_daily_run_steps.build(step_name: target_step, status: "skipped") ]
    end

    def dry_run_result(diagnostic, selected_steps)
      Result.new(
        mode: "dry_run",
        target_date:,
        source: "manual",
        daily_run: diagnostic.latest_run,
        retry_limit_bypassed: diagnostic.retry_limit_reached || diagnostic.blocking_reason == "step_retry_limit_reached",
        blocking_reason: diagnostic.blocking_reason,
        selected_steps: selected_steps.map(&:step_name),
        executed_steps: [],
        skipped_steps: [],
        success: true,
        message: "dry-run only"
      )
    end

    def blocked_result(diagnostic, message)
      Result.new(
        mode: apply? ? "apply" : "dry_run",
        target_date:,
        source: "manual",
        daily_run: diagnostic.latest_run,
        retry_limit_bypassed: false,
        blocking_reason: diagnostic.blocking_reason,
        selected_steps: [],
        executed_steps: [],
        skipped_steps: [],
        success: false,
        message:
      )
    end

    def record_manual_bypass!(run, step)
      now = Time.current
      step.update!(
        metadata: step.metadata.to_h.merge(
          "manual_retry_bypass" => {
            "execution_source" => "manual",
            "retry_limit_bypassed" => true,
            "retry_limit_bypass_reason" => "explicit_manual_run",
            "requested_at" => now.iso8601,
            "requested_by" => requested_by,
            "target_step" => step.step_name
          }
        )
      )
      run.update!(
        run_log: [
          run.run_log.presence,
          "[#{now.iso8601}] Manual Daily Run recovery requested step=#{step.step_name} retry_limit_bypassed=true requested_by=#{requested_by}"
        ].compact.join("\n")
      )
      Rails.logger.info(
        "[AicooDailyRunManualRunner] source=manual target_date=#{run.target_date} " \
        "run_id=#{run.id} retry_limit_bypassed=true bypass_reason=explicit_manual_run " \
        "selected_recovery_steps=#{step.step_name}"
      )
    end
  end
end
