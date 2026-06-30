module Aicoo
  class PipelineStuckDetector
    Result = Data.define(:checked_count, :stuck_runs, :recovered_logs)

    THRESHOLDS = {
      "discovery" => 30.minutes,
      "score" => 30.minutes,
      "serp" => 30.minutes,
      "lp" => 30.minutes,
      "publish" => 15.minutes,
      "measure" => 30.minutes,
      "improve" => 1.hour,
      "deploy" => 30.minutes,
      "learning" => 30.minutes,
      "decision" => 1.hour
    }.freeze

    AUTO_RECOVERY_ACTIONS = {
      "api_failed" => "retry",
      "codex_failed" => "retry",
      "deploy_failed" => "request_approval",
      "validation_failed" => "request_approval"
    }.freeze

    def initialize(scope: AicooPipelineRun.active, auto_recover: true)
      @scope = scope
      @auto_recover = auto_recover
      @stuck_runs = []
      @recovered_logs = []
    end

    def call
      runs = scope.includes(:business, :idea_pipeline_item, :aicoo_lab_landing_page).find_each.to_a
      runs.each { |run| inspect_run(run) }

      Result.new(checked_count: runs.size, stuck_runs:, recovered_logs:)
    end

    private

    attr_reader :scope, :auto_recover, :stuck_runs, :recovered_logs

    def inspect_run(run)
      detection = detect(run)
      unless detection
        clear_stuck!(run)
        return
      end

      run.update!(
        stuck: true,
        stuck_reason: detection.fetch(:reason),
        stuck_detected_at: run.stuck_detected_at || Time.current,
        auto_recoverable: detection.fetch(:auto_recoverable),
        recovery_action: detection.fetch(:action),
        recovery_message: detection.fetch(:message),
        halted_reason: detection.fetch(:reason)
      )
      stuck_runs << run

      return unless auto_recover && detection.fetch(:auto_recoverable)

      log = Aicoo::PipelineRecoveryService.new(run, action: detection.fetch(:action), source: "detector").call
      recovered_logs << log
    end

    def detect(run)
      return if terminal?(run)
      return if expected_waiting_data?(run)
      return if serp_optional_missing?(run)
      return unless elapsed_too_long?(run)

      reason = stuck_reason(run)
      action = AUTO_RECOVERY_ACTIONS[reason]
      {
        reason:,
        action:,
        auto_recoverable: action.present? && retry_allowed?(run, reason),
        message: recovery_message(run, reason, action)
      }
    end

    def terminal?(run)
      run.status.in?(%w[completed ended])
    end

    def expected_waiting_data?(run)
      run.current_stage == "measure" &&
        run.waiting_reason == "published_sample_window" &&
        run.waiting_until.present? &&
        Time.zone.parse(run.waiting_until.to_s).future?
    rescue ArgumentError, TypeError
      false
    end

    def elapsed_too_long?(run)
      threshold = THRESHOLDS.fetch(run.current_stage, 30.minutes)
      reference_time(run) <= threshold.ago
    end

    def reference_time(run)
      state = run.current_stage_state
      parse_time(state["started_at"]) ||
        parse_time(state["finished_at"]) ||
        run.stuck_detected_at ||
        run.updated_at ||
        run.created_at
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def stuck_reason(run)
      return "waiting_approval" if run.status == "approval_waiting"
      return "waiting_budget" if run.status == "budget_blocked"
      return "deploy_failed" if deploy_failed?(run)
      return "codex_failed" if codex_failed?(run)
      return "missing_google_connection" if missing_google_connection?(run)
      return "missing_serp_key" if missing_serp_key?(run)
      return "missing_execution_profile" if missing_execution_profile?(run)
      return "api_failed" if api_failed?(run)
      return "validation_failed" if validation_failed?(run)

      "unknown"
    end

    def deploy_failed?(run)
      run.current_stage == "deploy" &&
        run.business&.auto_revision_run_logs&.recent&.first&.deploy_result == "failed"
    end

    def codex_failed?(run)
      run.current_stage.in?(%w[improve deploy]) &&
        run.business&.auto_revision_run_logs&.recent&.first&.status == "failed"
    end

    def missing_google_connection?(run)
      return false unless run.current_stage.in?(%w[measure improve deploy learning])

      AicooGoogleCredential.default&.refresh_token.blank?
    end

    def missing_serp_key?(run)
      return false unless run.current_stage == "serp"

      Aicoo::Serp::OptionalMode.call.missing_key?
    end

    def serp_optional_missing?(run)
      run.current_stage == "serp" && missing_serp_key?(run)
    end

    def missing_execution_profile?(run)
      business = run.business
      return false unless business && run.current_stage.in?(%w[improve deploy])
      return false if business.aicoo_internal_codex?

      business.business_execution_profile&.coverage_status != "configured"
    end

    def api_failed?(run)
      run.last_error.to_s.match?(/api|timeout|rate|http|google|serp/i) ||
        run.current_stage_state["last_error"].to_s.match?(/api|timeout|rate|http|google|serp/i)
    end

    def validation_failed?(run)
      run.status == "blocked" || run.current_stage_state["status"] == "blocked"
    end

    def retry_allowed?(run, reason)
      return true unless reason.in?(%w[api_failed codex_failed])

      run.retry_count.to_i < max_retry_count(run)
    end

    def max_retry_count(run)
      run.retry_schedule.to_h["max_retry_count"].presence || Aicoo::Pipeline::RetryEngine::DEFAULT_INTERVALS.size
    end

    def recovery_message(run, reason, action)
      return next_step_for(reason) if action.blank?

      "#{next_step_for(reason)} 自動復旧: #{action} を実行します。"
    end

    def next_step_for(reason)
      {
        "waiting_approval" => "承認して進める必要があります。",
        "waiting_budget" => "予算設定を確認してください。",
        "missing_google_connection" => "Google連携を設定してください。",
        "missing_serp_key" => Aicoo::Serp::OptionalMode::WARNING_MESSAGE,
        "missing_execution_profile" => "Execution Profileを設定してください。",
        "codex_failed" => "Codex実行の再試行または承認が必要です。",
        "deploy_failed" => "Deploy承認待ちへ落とします。",
        "api_failed" => "API取得を再試行します。",
        "validation_failed" => "承認待ちへ落として内容を確認します。",
        "unknown" => "Pipeline詳細を確認してください。"
      }.fetch(reason, "Pipeline詳細を確認してください。")
    end

    def clear_stuck!(run)
      return unless run.stuck?

      run.update!(
        stuck: false,
        stuck_reason: nil,
        stuck_detected_at: nil,
        auto_recoverable: false,
        recovery_action: nil,
        recovery_message: nil
      )
    end
  end
end
