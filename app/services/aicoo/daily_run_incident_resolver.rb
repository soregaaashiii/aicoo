module Aicoo
  class DailyRunIncidentResolver
    ORDER_SQL = "aicoo_daily_runs.id DESC, COALESCE(aicoo_daily_run_steps.started_at, aicoo_daily_run_steps.created_at) DESC".freeze

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
      :exclusion_reason,
      :recovery_comparison_method
    )
    Recovery = Data.define(
      :recovered,
      :reason,
      :step_name,
      :latest_success_step,
      :latest_step,
      :latest_failure_run_id,
      :latest_failure_at,
      :latest_success_run_id,
      :latest_success_at,
      :comparison_method
    )

    def self.call(window: 7.days.ago..Time.current, limit: 100)
      new(window:, limit:).call
    end

    def self.recovery_for_step(step_name, latest_failure_run_id: nil, latest_failure_step: nil, latest_failure_at: nil)
      new.recovery_for_step(step_name, latest_failure_run_id:, latest_failure_step:, latest_failure_at:)
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
          "ranking_row_latest_failure_step_id=#{incident.latest_failure_step&.id}",
          "ranking_row_latest_failure_created_at=#{incident.latest_failure_step&.created_at&.iso8601}",
          "ranking_row_latest_failure_started_at=#{incident.latest_failure_step&.started_at&.iso8601}",
          "ranking_row_latest_failure_updated_at=#{incident.latest_failure_step&.updated_at&.iso8601}",
          "ranking_row_latest_success_run_id=#{latest_success&.aicoo_daily_run_id}",
          "ranking_row_latest_success_step_id=#{latest_success&.id}",
          "ranking_row_latest_success_created_at=#{latest_success&.created_at&.iso8601}",
          "ranking_row_latest_success_started_at=#{latest_success&.started_at&.iso8601}",
          "ranking_row_latest_success_updated_at=#{latest_success&.updated_at&.iso8601}",
          "ranking_row_recovery_comparison_method=#{incident.recovery_comparison_method}",
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

    def recovery_for_step(step_name, latest_failure_run_id: nil, latest_failure_step: nil, latest_failure_at: nil)
      return Recovery.new(false, "step_name_missing", nil, nil, nil, latest_failure_run_id, latest_failure_at, nil, nil, "missing_step_name") if step_name.blank?

      latest_step = latest_step_for(step_name)
      latest_success_step = latest_success_step_for(step_name)
      failure_run_id = latest_failure_run_id || latest_failure_step&.aicoo_daily_run_id
      failure_at = latest_failure_at || stable_timestamp_for(latest_failure_step)

      if latest_step&.status == "success" && success_after_failure?(latest_step, failure_run_id:, failure_at:)
        return Recovery.new(
          true,
          "latest_step_success",
          step_name,
          latest_step,
          latest_step,
          failure_run_id,
          failure_at,
          latest_step.aicoo_daily_run_id,
          stable_timestamp_for(latest_step),
          comparison_method_for(latest_step, failure_run_id:, failure_at:)
        )
      end

      if latest_success_step && success_after_failure?(latest_success_step, failure_run_id:, failure_at:)
        return Recovery.new(
          true,
          "latest_success_after_failure",
          step_name,
          latest_success_step,
          latest_step,
          failure_run_id,
          failure_at,
          latest_success_step.aicoo_daily_run_id,
          stable_timestamp_for(latest_success_step),
          comparison_method_for(latest_success_step, failure_run_id:, failure_at:)
        )
      end

      Recovery.new(
        false,
        "latest_success_not_found_after_failure",
        step_name,
        latest_success_step,
        latest_step,
        failure_run_id,
        failure_at,
        latest_success_step&.aicoo_daily_run_id,
        stable_timestamp_for(latest_success_step),
        comparison_method_for(latest_success_step, failure_run_id:, failure_at:)
      )
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
      sorted = runs.sort_by(&:id)
      latest = sorted.last
      oldest = sorted.first
      step = last_step(latest)
      step_name = step&.step_name.presence || "unknown_step"
      root_cause = reason(latest, step)
      latest_failure_at = stable_timestamp_for(step) || latest.started_at || latest.created_at
      recovery = recovery_for_step(step_name, latest_failure_run_id: latest.id, latest_failure_step: step, latest_failure_at:)

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
        exclusion_reason: recovery.recovered ? recovery.reason : nil,
        recovery_comparison_method: recovery.comparison_method
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

    def stable_timestamp_for(record)
      return unless record

      record.started_at || record.created_at
    end

    def success_after_failure?(success_step, failure_run_id:, failure_at:)
      return false unless success_step

      success_run_id = success_step.aicoo_daily_run_id
      return success_run_id > failure_run_id if success_run_id.present? && failure_run_id.present?

      success_at = stable_timestamp_for(success_step)
      return false if success_at.blank?
      return true if failure_at.blank?

      success_at > failure_at
    end

    def comparison_method_for(success_step, failure_run_id:, failure_at:)
      return "no_success_step" unless success_step
      return "run_id" if success_step.aicoo_daily_run_id.present? && failure_run_id.present?
      return "started_at_or_created_at" if stable_timestamp_for(success_step).present? || failure_at.present?

      "insufficient_comparison_inputs"
    end
  end
end
