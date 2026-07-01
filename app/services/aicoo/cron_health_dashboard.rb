module Aicoo
  class CronHealthDashboard
    RUNNING_STUCK_AFTER = 30.minutes
    HISTORY_LIMIT = 30

    Summary = Data.define(
      :status,
      :severity,
      :title,
      :message,
      :last_success_at,
      :duration_label,
      :success_rate,
      :latest_run,
      :warnings
    )
    Warning = Data.define(:key, :severity, :title, :message)
    StepRow = Data.define(:step, :name, :status, :severity, :started_at, :finished_at, :duration_label, :warning, :error_message)
    HistoryRow = Data.define(:run, :duration_label, :success_count, :failed_count, :retry_count, :trigger_label)

    def call
      self
    end

    def latest_run
      @latest_run ||= AicooDailyRun.includes(:aicoo_daily_run_steps).recent.first
    end

    def latest_cron_run
      @latest_cron_run ||= AicooDailyRun.where(source: "cron").includes(:aicoo_daily_run_steps).recent.first
    end

    def latest_success_run
      @latest_success_run ||= AicooDailyRun.successful.recent.first
    end

    def latest_failed_run
      @latest_failed_run ||= AicooDailyRun.where(status: %w[failed partial_failed stuck]).recent.first
    end

    def today_runs
      @today_runs ||= AicooDailyRun.where(created_at: Time.zone.today.all_day)
    end

    def history_runs
      @history_runs ||= AicooDailyRun.includes(:aicoo_daily_run_steps).recent.limit(HISTORY_LIMIT)
    end

    def scheduler_status
      @scheduler_status ||= AicooDailyRunScheduler.status
    end

    def summary
      Summary.new(
        status: display_status,
        severity: summary_severity,
        title: summary_title,
        message: summary_message,
        last_success_at: latest_success_run&.finished_at,
        duration_label: latest_run ? duration_label(latest_run.started_at, latest_run.finished_at, nil) : "-",
        success_rate: today_success_rate,
        latest_run:,
        warnings:
      )
    end

    def last_cron_started_at
      latest_cron_run&.started_at
    end

    def last_cron_finished_at
      latest_cron_run&.finished_at
    end

    def last_success_at
      latest_success_run&.finished_at
    end

    def last_failure_at
      latest_failed_run&.finished_at || latest_failed_run&.created_at
    end

    def status
      display_status
    end

    def duration_label_for_latest
      latest_run ? duration_label(latest_run.started_at, latest_run.finished_at, nil) : "-"
    end

    def today_run_count
      today_runs.count
    end

    def today_success_count
      today_runs.where(status: AicooDailyRun::SUCCESS_STATUSES).count
    end

    def today_failure_count
      today_runs.where(status: %w[failed partial_failed stuck]).count
    end

    def today_skip_count
      today_runs.where(status: "skipped").count
    end

    def retry_count
      latest_run&.retry_count.to_i
    end

    def stuck_count
      today_runs.where(status: "stuck").count + stale_running_runs.count
    end

    def latest_run_reason
      return "-" unless latest_run

      latest_run.run_log.to_s.lines.last&.strip.presence || latest_run.error_message.presence || scheduler_status.reason
    end

    def latest_run_environment
      trigger_label(latest_run)
    end

    def latest_step_rows
      return [] unless latest_run

      Aicoo::DailyRunHistory.new(latest_run).step_rows.map do |row|
        StepRow.new(
          step: row.record,
          name: row.name,
          status: row.status,
          severity: severity_for_step(row),
          started_at: row.started_at,
          finished_at: row.finished_at,
          duration_label: row.duration_label,
          warning: row.visual_status == "warning" ? row.reason : "-",
          error_message: row.error_message.presence || "-"
        )
      end
    end

    def history_rows
      history_runs.map do |run|
        steps = run.aicoo_daily_run_steps
        HistoryRow.new(
          run:,
          duration_label: duration_label(run.started_at, run.finished_at, nil),
          success_count: steps.count { |step| step.status == "success" },
          failed_count: steps.count { |step| step.status == "failed" },
          retry_count: run.retry_count,
          trigger_label: trigger_label(run)
        )
      end
    end

    def recoverable_steps
      return [] unless latest_run

      latest_run.aicoo_daily_run_steps.select(&:recovery_available?)
    end

    def warnings
      @warnings ||= build_warnings
    end

    private

    def build_warnings
      [].tap do |items|
        items << Warning.new(:cron_disabled, "warning", "Cron ENVが無効です", "AICOO_DAILY_RUN_ENABLED=true ではないため、Render CronからはDaily Runを起動しません。") unless Aicoo::DailyRunCronTask.enabled?
        items << Warning.new(:no_success_today, "warning", "今日はまだ成功していません", "今日のDaily Run成功履歴がありません。Cron時刻・Scheduler状態・最新Runを確認してください。") if today_success_count.zero?
        if stale_running_runs.any?
          items << Warning.new(:stale_running, "critical", "Runningが30分以上続いています", "Daily Runがrunningのまま止まっている可能性があります。Scheduler診断または再実行を確認してください。")
        end
        items << Warning.new(:retrying, "warning", "Retryが連続しています", "最新Runのretry_countが#{retry_count}です。失敗stepを確認してください。") if retry_count >= 2
        items << Warning.new(:high_failure_rate, "critical", "Failure率が高いです", "今日のDaily Run失敗率が50%以上です。Error Messageを確認してください。") if today_run_count >= 2 && today_failure_count.to_f / today_run_count >= 0.5
        items.concat(api_warnings)
      end
    end

    def api_warnings
      messages = latest_error_messages
      [].tap do |items|
        items << Warning.new(:env_missing, "warning", "ENV不足の可能性があります", "ENVまたは接続設定不足でskip/warningになったstepがあります。") if messages.match?(/ENV|missing|未設定|not configured|credentials_json_source=missing/i)
        items << Warning.new(:openai_error, "warning", "OpenAI APIエラー", "OpenAI API関連のエラーが最新Runに含まれています。") if messages.match?(/openai/i)
        items << Warning.new(:google_error, "warning", "Google APIエラー", "Google APIまたはOAuth関連のエラーが最新Runに含まれています。") if messages.match?(/google|ga4|gsc|oauth|refresh token|invalid_grant/i)
        items << Warning.new(:activity_api_error, "warning", "Activity APIエラー", "Activity APIまたはActivity Learning関連のエラーが最新Runに含まれています。") if messages.match?(/activity/i)
      end
    end

    def latest_error_messages
      return "" unless latest_run

      step_messages = latest_run.aicoo_daily_run_steps.flat_map do |step|
        [ step.error_message, step.metadata.to_h["message"], step.metadata.to_h["reason"] ]
      end
      ([ latest_run.error_message, latest_run.run_log ] + step_messages).compact.join("\n")
    end

    def stale_running_runs
      @stale_running_runs ||= AicooDailyRun.running.where("started_at < ?", RUNNING_STUCK_AFTER.ago)
    end

    def display_status
      return "disabled" unless Aicoo::DailyRunCronTask.enabled?
      return "running" if latest_run&.running?

      latest_run&.status || "skipped"
    end

    def summary_severity
      return "critical" if warnings.any? { |warning| warning.severity == "critical" }
      return "warning" if warnings.any?
      return "healthy" if latest_success_run

      "attention"
    end

    def summary_title
      case summary_severity
      when "healthy" then "Daily Run 正常"
      when "critical" then "Daily Run 要確認"
      when "warning" then "Daily Run 注意"
      else "Daily Run 未実行"
      end
    end

    def summary_message
      return warnings.first.message if warnings.any?
      return "最終成功: #{I18n.l(latest_success_run.finished_at, format: :short)} / 成功率: #{today_success_rate}%" if latest_success_run

      "Daily Run履歴がまだありません。"
    end

    def today_success_rate
      return 0 if today_run_count.zero?

      ((today_success_count.to_f / today_run_count) * 100).round
    end

    def severity_for_step(row)
      case row.visual_status
      when "success" then "healthy"
      when "warning" then "warning"
      when "failed" then "critical"
      when "running" then "attention"
      else "attention"
      end
    end

    def trigger_label(run)
      return "-" unless run

      case run.source
      when "cron" then "Render Cron"
      when "manual" then "Manual"
      when "catch_up" then "Catch Up"
      else run.source
      end
    end

    def duration_label(started_at, finished_at, duration_seconds)
      seconds = duration_seconds || calculated_duration(started_at, finished_at)
      return "-" unless seconds

      seconds = seconds.to_i
      return "#{seconds}秒" if seconds < 60

      minutes = seconds / 60
      remaining_seconds = seconds % 60
      return "#{minutes}分#{remaining_seconds}秒" if minutes < 60

      hours = minutes / 60
      remaining_minutes = minutes % 60
      "#{hours}時間#{remaining_minutes}分"
    end

    def calculated_duration(started_at, finished_at)
      return nil unless started_at

      ((finished_at || Time.current) - started_at).to_i
    end
  end
end
