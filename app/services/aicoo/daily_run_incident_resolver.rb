module Aicoo
  class DailyRunIncidentResolver
    ORDER_SQL = "COALESCE(aicoo_daily_run_steps.finished_at, aicoo_daily_run_steps.updated_at, aicoo_daily_run_steps.created_at) DESC".freeze

    Incident = Data.define(
      :key,
      :runs,
      :latest_run,
      :oldest_run,
      :step_name,
      :root_cause,
      :latest_failure_step,
      :latest_success_step,
      :latest_step,
      :recovered,
      :exclusion_reason
    )
    Recovery = Data.define(
      :recovered,
      :reason,
      :step_name,
      :latest_success_step,
      :latest_step,
      :latest_failure_at,
      :latest_success_at
    )

    def self.call(window: 7.days.ago..Time.current, limit: 100)
      new(window:, limit:).call
    end

    def self.recovery_for_step(step_name, latest_failure_at: nil)
      new.recovery_for_step(step_name, latest_failure_at:)
    end

    def self.log_ranking_decision!(incident, included:)
      latest_success = incident.latest_success_step
      latest_failure = incident.latest_run
      Rails.logger.info(
        [
          "ranking_row_title=#{ranking_title(incident).inspect}",
          "ranking_row_source_class=AicooDailyRun",
          "ranking_row_candidate_id=nil",
          "ranking_row_step_name=#{incident.step_name}",
          "ranking_row_latest_failure_run_id=#{latest_failure&.id}",
          "ranking_row_latest_success_run_id=#{latest_success&.aicoo_daily_run_id}",
          "ranking_row_included=#{included}",
          "ranking_row_exclusion_reason=#{incident.exclusion_reason}"
        ].join(" ")
      )
    end

    def self.ranking_title(incident)
      status_label = incident.latest_run&.status == "partial_failed" ? "一部失敗" : "停止"
      "Daily Runが #{incident.step_name.presence || 'unknown_step'} で継続#{status_label}"
    end

    def initialize(window: 7.days.ago..Time.current, limit: 100)
      @window = window
      @limit = limit
    end

    def call
      grouped_runs.map { |runs| build_incident(runs) }
    end

    def recovery_for_step(step_name, latest_failure_at: nil)
      return Recovery.new(false, "step_name_missing", nil, nil, nil, latest_failure_at, nil) if step_name.blank?

      latest_step = latest_step_for(step_name)
      latest_success_step = latest_success_step_for(step_name)
      latest_success_at = timestamp_for(latest_success_step)

      if latest_step&.status == "success" && after_or_without_failure?(timestamp_for(latest_step), latest_failure_at)
        return Recovery.new(true, "latest_step_success", step_name, latest_step, latest_step, latest_failure_at, timestamp_for(latest_step))
      end

      if latest_success_step && after_or_without_failure?(latest_success_at, latest_failure_at)
        return Recovery.new(true, "latest_success_after_failure", step_name, latest_success_step, latest_step, latest_failure_at, latest_success_at)
      end

      Recovery.new(false, "latest_success_not_found_after_failure", step_name, latest_success_step, latest_step, latest_failure_at, latest_success_at)
    end

    private

    attr_reader :window, :limit

    def grouped_runs
      AicooDailyRun
        .actual_runs
        .where(created_at: window)
        .where(status: %w[failed partial_failed stuck])
        .includes(:aicoo_daily_run_steps)
        .recent
        .limit(limit)
        .to_a
        .group_by { |run| dedupe_key(run) }
        .values
    end

    def build_incident(runs)
      sorted = runs.sort_by { |run| [ run.started_at || run.created_at, run.id ] }
      latest = sorted.last
      oldest = sorted.first
      step = last_step(latest)
      step_name = step&.step_name.presence || "unknown_step"
      root_cause = reason(latest, step)
      latest_failure_at = timestamp_for(step) || latest.finished_at || latest.updated_at || latest.created_at
      recovery = recovery_for_step(step_name, latest_failure_at:)

      Incident.new(
        key: dedupe_key(latest),
        runs: sorted,
        latest_run: latest,
        oldest_run: oldest,
        step_name:,
        root_cause:,
        latest_failure_step: step,
        latest_success_step: recovery.latest_success_step,
        latest_step: recovery.latest_step,
        recovered: recovery.recovered,
        exclusion_reason: recovery.recovered ? recovery.reason : nil
      )
    end

    def dedupe_key(run)
      step = last_step(run)
      [
        "daily_run",
        step&.step_name.presence || "unknown_step",
        normalized_reason(reason(run, step))
      ].join(":")
    end

    def last_step(run)
      steps = run.aicoo_daily_run_steps.to_a
      steps.select { |step| step.status == "running" }
           .max_by { |step| [ step.started_at || Time.zone.at(0), step.created_at, step.id ] } ||
        steps.max_by { |step| [ step.started_at || step.finished_at || Time.zone.at(0), step.created_at, step.id ] }
    end

    def reason(run, step)
      step&.error_message.presence ||
        step&.metadata.to_h["error"].presence ||
        step&.metadata.to_h["exception"].presence ||
        step&.metadata.to_h["message"].presence ||
        run.error_message.presence ||
        run.calibration_error.presence ||
        "Run Logを確認してください。"
    end

    def normalized_reason(reason)
      reason.to_s.squish.first(120).presence || "unknown"
    end

    def latest_step_for(step_name)
      steps_for(step_name).first
    end

    def latest_success_step_for(step_name)
      steps_for(step_name).successful.first
    end

    def steps_for(step_name)
      AicooDailyRunStep
        .joins(:aicoo_daily_run)
        .merge(AicooDailyRun.actual_runs)
        .where(step_name:)
        .order(Arel.sql(ORDER_SQL), id: :desc)
    end

    def timestamp_for(record)
      return unless record

      record.finished_at || record.updated_at || record.created_at
    end

    def after_or_without_failure?(success_at, failure_at)
      return false if success_at.blank?
      return true if failure_at.blank?

      success_at >= failure_at
    end
  end
end
