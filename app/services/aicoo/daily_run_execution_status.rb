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
      :path
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
      @running_rows ||= AicooDailyRun.running
        .includes(:aicoo_daily_run_steps)
        .recent
        .map { |run| build_row(run) }
    end

    def latest_run
      @latest_run ||= AicooDailyRun.includes(:aicoo_daily_run_steps).recent.first
    end

    def build_row(run)
      current_step = run.current_step
      Row.new(
        run:,
        run_id: run.id,
        status: run.status,
        source: run.source,
        target_date: run.target_date,
        started_at: run.started_at,
        current_step_name: current_step&.step_name || "準備中",
        elapsed_label: run.running_duration_label,
        stuck: stuck?(run),
        last_log: last_log_for(run, current_step),
        path: aicoo_daily_run_path(run)
      )
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
