module Aicoo
  class DailyRunExecutionStatus
    STUCK_AFTER = 30.minutes

    Row = Data.define(
      :run,
      :run_id,
      :status,
      :source,
      :target_date,
      :started_at,
      :current_step_name,
      :elapsed_label,
      :stuck,
      :last_log,
      :path,
      :progress
    ) do
      def stuck?
        stuck
      end

      def status_label
        stuck? ? "stuckの可能性あり" : "実行中"
      end
    end

    Result = Data.define(:rows, :latest_run) do
      def running?
        rows.any?
      end

      def empty?
        rows.empty?
      end

      def status_label
        return "stuckの可能性あり" if rows.any?(&:stuck?)
        return "実行中" if running?
        return "最終実行は完了済み" if latest_run&.succeeded?
        return "最終実行は要確認" if latest_run&.failed?

        "未実行"
      end
    end

    include Rails.application.routes.url_helpers

    def self.call
      new.call
    end

    def call
      Result.new(rows: running_rows, latest_run:)
    end

    private

    def running_rows
      @running_rows ||= active_runs
        .includes(:aicoo_daily_run_steps)
        .recent
        .then { |runs| build_rows(runs) }
    end

    def latest_run
      @latest_run ||= AicooDailyRun.includes(:aicoo_daily_run_steps).recent.first
    end

    def active_runs
      AicooDailyRun.running
    end

    def build_rows(runs)
      records = runs.to_a
      progress_by_id = Aicoo::DailyRunProgress.for_runs(records)
      records.map { |run| build_row(run, progress_by_id.fetch(run)) }
    end

    def build_row(run, progress)
      Row.new(
        run:,
        run_id: run.id,
        status: run.status,
        source: run.source,
        target_date: run.target_date,
        started_at: run.started_at,
        current_step_name: progress.current_step_label,
        elapsed_label: progress.elapsed_label,
        stuck: stuck?(run),
        last_log: last_log_for(run, current_step_for(progress)),
        path: aicoo_daily_run_path(run),
        progress:
      )
    end

    def current_step_for(progress)
      progress.run.aicoo_daily_run_steps.find { |step| step.step_name == progress.current_step_name && step.status == "running" }
    end

    def stuck?(run)
      run.started_at.present? && run.started_at < STUCK_AFTER.ago
    end

    def last_log_for(run, current_step)
      [
        current_step&.error_message,
        current_step&.metadata.to_h["message"],
        run.run_log.to_s.lines.last&.strip,
        run.error_message
      ].compact_blank.first.to_s.truncate(140)
    end
  end
end
