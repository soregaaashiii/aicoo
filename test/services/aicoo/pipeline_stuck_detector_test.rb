require "test_helper"

module Aicoo
  class PipelineStuckDetectorTest < ActiveSupport::TestCase
    test "does not mark missing serp key as stuck because serp is optional" do
      run = create_run(current_stage: "serp", status: "running")
      DataSourceCostProfile.find_or_create_by!(source_key: "serp") do |profile|
        profile.name = "SERP"
        profile.execution_mode = "manual"
      end.update!(api_key: nil)

      result = PipelineStuckDetector.new(scope: AicooPipelineRun.where(id: run.id), auto_recover: true).call

      assert_equal 1, result.checked_count
      assert_empty result.stuck_runs
      assert_not run.reload.stuck?
      assert_nil run.stuck_reason
      assert_empty result.recovered_logs
    end

    test "does not mark measure sample waiting as stuck" do
      run = create_run(
        current_stage: "measure",
        status: "waiting",
        waiting_reason: "published_sample_window",
        waiting_until: 10.days.from_now.iso8601
      )

      result = PipelineStuckDetector.new(scope: AicooPipelineRun.where(id: run.id), auto_recover: true).call

      assert_empty result.stuck_runs
      assert_not run.reload.stuck?
    end

    test "auto retries api failure and logs recovery" do
      create_google_credential
      run = create_run(current_stage: "learning", status: "running", last_error: "API timeout")

      result = PipelineStuckDetector.new(scope: AicooPipelineRun.where(id: run.id), auto_recover: true).call

      assert_equal "api_failed", run.reload.stuck_reason
      assert_equal "retry_waiting", run.status
      assert_equal 1, run.retry_count
      assert_equal 1, result.recovered_logs.size
      assert_equal "retry", result.recovered_logs.first.action
      assert result.recovered_logs.first.success?
    end

    test "missing google connection becomes owner task without auto recovery" do
      AicooGoogleCredential.delete_all
      run = create_run(current_stage: "improve", status: "running")

      PipelineStuckDetector.new(scope: AicooPipelineRun.where(id: run.id), auto_recover: true).call

      assert_equal "missing_google_connection", run.reload.stuck_reason
      assert_not run.auto_recoverable?
      assert_equal "Google連携を設定してください。", run.recovery_message
    end

    test "deploy failure falls back to approval waiting and logs recovery" do
      business = businesses(:suelog)
      business.auto_revision_run_logs.create!(
        status: "failed",
        auto_revision_mode: "automatic",
        risk_level: "low",
        deploy_result: "failed",
        message: "Deploy failed"
      )
      run = create_run(business:, current_stage: "deploy", status: "running")

      result = PipelineStuckDetector.new(scope: AicooPipelineRun.where(id: run.id), auto_recover: true).call

      assert_equal "deploy_failed", run.reload.stuck_reason
      assert_equal "approval_waiting", run.status
      assert_equal 1, result.recovered_logs.size
      assert_equal "approve", result.recovered_logs.first.action
      assert result.recovered_logs.first.success?
    end

    test "manual recovery can skip stage" do
      run = create_run(current_stage: "lp", status: "blocked")
      run.update!(stuck: true, stuck_reason: "validation_failed")

      log = PipelineRecoveryService.new(run, action: "skip", source: "test").call

      assert log.success?
      assert_equal "running", run.reload.status
      assert_equal "skipped", run.stage_state("lp")["status"]
      assert_equal "skip", log.action
    end

    private

    def create_run(business: businesses(:suelog), current_stage:, status:, waiting_reason: nil, waiting_until: nil, last_error: nil)
      entered_at = 2.hours.ago
      AicooPipelineRun.create!(
        pipeline_type: "business",
        business:,
        status:,
        current_stage:,
        started_at: 1.day.ago,
        retry_count: 0,
        last_error:,
        waiting_reason:,
        waiting_until:,
        stage_states: {
          current_stage => {
            "status" => status == "blocked" ? "blocked" : "open",
            "started_at" => entered_at.iso8601,
            "message" => "test stage"
          }
        },
        gate_snapshot: {},
        budget_snapshot: {},
        retry_schedule: { "max_retry_count" => 4 },
        metadata: { "stage_entered_at" => entered_at.iso8601 }
      )
    end

    def create_google_credential
      AicooGoogleCredential.create!(
        name: "Pipeline Stuck Test Google",
        client_id: "123-test.apps.googleusercontent.com",
        client_secret: "secret",
        refresh_token: "refresh"
      )
    end
  end
end
