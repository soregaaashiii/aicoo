module Aicoo
  class DailyRunStuckDiagnostic
    Row = Data.define(
      :run,
      :last_successful_step,
      :last_started_step,
      :last_running_step,
      :elapsed_seconds,
      :exception,
      :heartbeat,
      :finished_at
    )

    def self.call(limit: 10, scope: nil)
      new(limit:, scope:).call
    end

    def initialize(limit: 10, scope: nil)
      @limit = limit
      @scope = scope
    end

    def call
      runs.map { |run| build_row(run) }
    end

    private

    attr_reader :limit, :scope

    def runs
      (scope || AicooDailyRun.where(status: "stuck"))
        .includes(:aicoo_daily_run_steps)
        .recent
        .limit(limit)
    end

    def build_row(run)
      steps = run.aicoo_daily_run_steps.to_a
      last_started_step = steps.max_by { |step| [ step.started_at || Time.zone.at(0), step.created_at ] }
      last_successful_step = steps.select { |step| step.status == "success" }
                                  .max_by { |step| [ step.finished_at || step.started_at || Time.zone.at(0), step.created_at ] }
      last_running_step = steps.select { |step| step.status == "running" }
                               .max_by { |step| [ step.started_at || Time.zone.at(0), step.created_at ] }

      Row.new(
        run:,
        last_successful_step:,
        last_started_step:,
        last_running_step:,
        elapsed_seconds: elapsed_seconds(run, last_running_step || last_started_step),
        exception: exception_for(run, last_running_step || last_started_step),
        heartbeat: heartbeat_for(last_running_step || last_started_step),
        finished_at: run.finished_at
      )
    end

    def elapsed_seconds(run, step)
      from = step&.started_at || run.started_at || run.created_at
      return 0 unless from

      to = run.finished_at || Time.current
      (to - from).to_i
    end

    def exception_for(run, step)
      step&.error_message.presence ||
        run.error_message.presence ||
        step&.metadata.to_h["error"].presence ||
        step&.metadata.to_h["exception"].presence ||
        step&.metadata.to_h["message"].presence
    end

    def heartbeat_for(step)
      return unless step

      metadata = step.metadata.to_h
      metadata["heartbeat"].presence ||
        metadata["heartbeat_at"].presence ||
        metadata.dig("memory_finish", "sampled_at").presence ||
        metadata.dig("memory_start", "sampled_at").presence ||
        step.updated_at&.iso8601
    end
  end
end
