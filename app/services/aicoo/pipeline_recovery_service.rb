module Aicoo
  class PipelineRecoveryService
    def initialize(run, action:, source: "manual")
      @run = run
      @action = action.to_s
      @source = source
    end

    def call
      before_status = run.status
      success = false
      error_message = nil

      ActiveRecord::Base.transaction do
        apply_action!
        success = true
      rescue StandardError => e
        error_message = "#{e.class}: #{e.message}"
        raise ActiveRecord::Rollback
      ensure
        @log = create_log!(before_status:, success:, error_message:)
      end

      log
    end

    private

    attr_reader :run, :action, :source, :log

    def apply_action!
      case action
      when "retry"
        retry_run!
      when "skip"
        skip_stage!
      when "approve", "request_approval"
        approve_or_request_approval!
      when "stop"
        stop_run!
      when "end"
        end_run!
      else
        raise ArgumentError, "Unsupported recovery action: #{action}"
      end
    end

    def retry_run!
      run.update!(
        status: "retry_waiting",
        retry_count: run.retry_count.to_i + 1,
        last_error: nil,
        auto_recoverable: false,
        recovery_action: nil,
        recovery_message: "再試行を予約しました。",
        metadata: run.metadata.to_h.merge("last_recovery_action" => "retry", "last_recovery_source" => source)
      )
    end

    def skip_stage!
      states = run.stage_states.to_h
      state = states[run.current_stage].to_h
      states[run.current_stage] = state.merge(
        "status" => "skipped",
        "reason" => "manual_recovery_skip",
        "message" => "復旧操作でスキップしました。",
        "finished_at" => Time.current.iso8601
      )
      run.update!(
        status: "running",
        stage_states: states,
        stuck: false,
        auto_recoverable: false,
        recovery_action: nil,
        recovery_message: "現在Stageをスキップしました。",
        metadata: run.metadata.to_h.merge("last_recovery_action" => "skip", "last_recovery_source" => source)
      )
    end

    def approve_or_request_approval!
      run.update!(
        status: "approval_waiting",
        auto_recoverable: false,
        recovery_action: nil,
        recovery_message: "承認待ちへ移動しました。",
        metadata: run.metadata.to_h.merge("last_recovery_action" => action, "last_recovery_source" => source)
      )
    end

    def stop_run!
      run.update!(
        status: "blocked",
        auto_recoverable: false,
        recovery_action: nil,
        recovery_message: "Pipelineを停止しました。",
        metadata: run.metadata.to_h.merge("last_recovery_action" => "stop", "last_recovery_source" => source)
      )
    end

    def end_run!
      run.update!(
        status: "ended",
        finished_at: Time.current,
        stuck: false,
        auto_recoverable: false,
        recovery_action: nil,
        recovery_message: "Pipelineを終了しました。",
        metadata: run.metadata.to_h.merge("last_recovery_action" => "end", "last_recovery_source" => source)
      )
    end

    def create_log!(before_status:, success:, error_message:)
      PipelineRecoveryLog.create!(
        aicoo_pipeline_run: run,
        business: run.business,
        stage: run.current_stage,
        stuck_reason: run.stuck_reason.presence || "unknown",
        action: action == "request_approval" ? "approve" : action,
        before_status:,
        after_status: run.reload.status,
        success:,
        error_message:,
        executed_at: Time.current,
        metadata: {
          "source" => source,
          "pipeline_type" => run.pipeline_type,
          "display_title" => run.display_title
        }
      )
    end
  end
end
