module Aicoo
  class DailyRunHistory
    StepRow = Data.define(
      :record,
      :name,
      :status,
      :visual_status,
      :started_at,
      :finished_at,
      :duration_label,
      :memory_label,
      :reason,
      :error_message,
      :metadata
    )

    SummaryCard = Data.define(:key, :label, :count, :status, :detail)
    ComparisonRow = Data.define(:run, :duration_label, :warning_count, :failed_count)

    SUMMARY_DEFINITIONS = [
      [ :analytics, "Analytics取得", %w[analytics_fetch], :analytics_fetch_count ],
      [ :serp, "SERP取得", %w[serp_fetch keyword_discovery competitor_serp_analysis serp_based_idea_generation], nil ],
      [ :snapshot, "Snapshot", %w[datahub_collect score_snapshot meta_evaluation_snapshot system_mode_snapshot], :snapshot_count ],
      [ :business_metrics, "BusinessMetricImport", %w[business_metrics_import], :business_metrics_imported_count ],
      [ :proxy_weight, "ProxyWeight", %w[proxy_weight_adjustment], :proxy_weights_adjusted_count ],
      [ :insight, "Insight", %w[insight_generation], :insight_generated_count ],
      [ :action_candidate, "ActionCandidate", %w[action_generation], :action_candidates_generated_count ],
      [ :action_result, "ActionResult", %w[action_result_evaluation], :action_results_evaluated_count ],
      [ :learning, "Learning", %w[activity_log_evaluation_queue_build business_playbook_update owner_task_digest], nil ],
      [ :calibration, "Calibration", %w[calibration], :updated_calibration_count ],
      [ :data_preparation, "Data Preparation", %w[data_preparation_queue], :data_preparation_candidates_count ],
      [ :auto_build, "Auto Build", %w[resource_aware_auto_build], nil ]
    ].freeze

    REASON_LABELS = {
      "serp_optional_missing" => "SERP Optional",
      "analytics_optional_unavailable" => "Google OAuth Expired",
      "already_success" => "Already Success Today",
      "not_due" => "Not Due",
      "disabled" => "Daily Run Disabled",
      "retry_limit_reached" => "Retry Limit Reached",
      "already_run" => "Already Run",
      "auto queue disabled" => "Auto Queue Disabled",
      "no_action_candidates_generated" => "No Candidate Generated",
      "no_insights_generated" => "No Insight Generated",
      "no_auto_revision_tasks_generated" => "No Auto Revision Generated",
      "no_eligible_candidates" => "No Eligible Candidate",
      "all_candidates_skipped" => "All Candidates Skipped"
    }.freeze

    def self.comparison_rows(limit: 10)
      AicooDailyRun.actual_runs.includes(:aicoo_daily_run_steps).recent.limit(limit).map do |run|
        new(run).comparison_row
      end
    end

    def initialize(daily_run)
      @daily_run = daily_run
    end

    attr_reader :daily_run

    def step_rows
      @step_rows ||= daily_run.aicoo_daily_run_steps.order(:started_at, :created_at).map do |step|
        StepRow.new(
          record: step,
          name: step.step_name,
          status: step.status,
          visual_status: visual_status(step),
          started_at: step.started_at,
          finished_at: step.finished_at,
          duration_label: duration_label(step.started_at, step.finished_at, step.duration_seconds),
          memory_label: memory_label(step.metadata.to_h),
          reason: reason_for(step),
          error_message: step.error_message,
          metadata: step.metadata.to_h
        )
      end
    end

    def summary_cards
      SUMMARY_DEFINITIONS.map do |key, label, step_names, counter_method|
        related_steps = step_rows.select { |row| step_names.include?(row.name) }
        SummaryCard.new(
          key:,
          label:,
          count: counter_method ? daily_run.public_send(counter_method).to_i : related_steps.size,
          status: summary_status(related_steps),
          detail: summary_detail(related_steps)
        )
      end
    end

    def error_rows
      step_rows.select { |row| row.visual_status == "failed" }
    end

    def warning_rows
      step_rows.select { |row| row.visual_status == "warning" }
    end

    def skipped_rows
      step_rows.select { |row| row.visual_status == "skipped" }
    end

    def warning_count
      warning_rows.size
    end

    def failed_count
      error_rows.size
    end

    def important_warning_count
      warning_rows.reject { |row| row.reason == "SERP Optional" }.size
    end

    def run_duration_label
      duration_label(daily_run.started_at, daily_run.finished_at, nil)
    end

    def comparison_row
      ComparisonRow.new(
        run: daily_run,
        duration_label: run_duration_label,
        warning_count:,
        failed_count:
      )
    end

    private

    def visual_status(step)
      return "warning" if warning_step?(step)

      step.status
    end

    def warning_step?(step)
      step.metadata.to_h["warning"] == true ||
        step.metadata.to_h["warning"] == "true" ||
        step.status == "skipped" && (
        step.metadata.to_h["warning"] == true ||
        step.metadata.to_h["warning"] == "true" ||
        step.metadata.to_h["reason"].to_s.in?(%w[serp_optional_missing analytics_optional_unavailable])
      )
    end

    def reason_for(step)
      raw_reason = step.metadata.to_h["reason"].presence || reason_from_error(step.error_message)
      REASON_LABELS.fetch(raw_reason.to_s, raw_reason.presence || "-")
    end

    def reason_from_error(error_message)
      message = error_message.to_s
      return "Google OAuth Expired" if message.match?(/invalid_grant|expired or revoked|refresh token/i)
      return "No Candidate Generated" if message.match?(/candidate.*0|generated.*0/i)

      nil
    end

    def summary_status(rows)
      return "success" if rows.empty?
      return "failed" if rows.any? { |row| row.visual_status == "failed" }
      return "warning" if rows.any? { |row| row.visual_status == "warning" }
      return "skipped" if rows.all? { |row| row.visual_status == "skipped" }
      return "running" if rows.any? { |row| row.visual_status == "running" }

      "success"
    end

    def summary_detail(rows)
      counts = rows.group_by(&:visual_status).transform_values(&:size)
      [
        "成功 #{counts.fetch('success', 0)}",
        "warning #{counts.fetch('warning', 0)}",
        "失敗 #{counts.fetch('failed', 0)}"
      ].join(" / ")
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

    def memory_label(metadata)
      start_mb = metadata.dig("memory_start", "rss_mb")
      finish_mb = metadata.dig("memory_finish", "rss_mb")
      delta_mb = metadata["memory_delta_mb"]
      return "-" if start_mb.blank? && finish_mb.blank?
      return "#{start_mb}MB → 実行中" if finish_mb.blank?

      delta_label = delta_mb.present? ? " / #{signed_delta(delta_mb)}MB" : ""
      "#{start_mb || '-'}MB → #{finish_mb}MB#{delta_label}"
    end

    def signed_delta(delta_mb)
      value = delta_mb.to_d
      return value.to_s if value.negative? || value.zero?

      "+#{value}"
    end

    def calculated_duration(started_at, finished_at)
      return nil unless started_at

      ((finished_at || Time.current) - started_at).to_i
    end
  end
end
