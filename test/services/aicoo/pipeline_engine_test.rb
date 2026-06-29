require "test_helper"

module Aicoo
  class PipelineEngineTest < ActiveSupport::TestCase
    test "syncs all stage states for an idea pipeline item" do
      item = create_item
      IdeaPipeline::IdeaScorer.new(item).call

      run = PipelineEngine.new(item.reload).call

      assert_equal "idea_pipeline", run.pipeline_type
      assert_equal item, run.idea_pipeline_item
      assert_equal AicooPipelineRun::STAGES.sort, run.stage_states.keys.sort
      assert_equal "done", run.stage_state("discovery")["status"]
      assert_includes AicooPipelineRun::STATUSES, run.status
      assert run.gate_snapshot["serp"].present?
      assert run.retry_schedule["retryable_stages"].include?("serp")
      assert run.budget_snapshot.key?("over_budget")
      assert run.metadata["pivot"].present?
    end

    test "low score skips serp and keeps lp open" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 40)
      IdeaPipeline::SerpEvaluator.new(item).call

      run = PipelineEngine.new(item.reload).call

      assert_equal "skipped", run.stage_state("serp")["status"]
      assert_equal "score_below_serp_threshold", run.stage_state("serp")["reason"]
      assert_equal "open", run.stage_state("lp")["status"]
    end

    test "published lp waits for measure window" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 70)
      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call
      landing_page.update!(
        public_status: "published",
        status: "published",
        published_slug: "pipeline-wait-test",
        published_at: 1.day.ago
      )

      run = PipelineEngine.new(item.reload).call

      assert_equal "waiting", run.stage_state("measure")["status"]
      assert_equal "published_sample_window", run.waiting_reason
      assert run.waiting_until.present?
    end

    test "budget gate blocks when projected cost exceeds monthly budget" do
      profile = DataSourceCostProfile.find_or_initialize_by(source_key: "serp")
      profile.update!(
        source_key: "serp",
        name: "SERP",
        execution_mode: "manual",
        monthly_budget_yen: 100,
        monthly_spend_yen: 90,
        average_cost_yen: 20
      )
      item = create_item
      item.update!(status: "owner_approved", final_score: 70)

      run = PipelineEngine.new(item).call

      assert_equal "budget_blocked", run.status
      assert_equal "monthly_budget_exceeded", run.halted_reason
      assert_equal true, run.budget_snapshot["over_budget"]
    end

    test "mvp and publication create business and pipeline links" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 80)
      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call
      IdeaPipeline::Publisher.new(item).call
      IdeaPipeline::MvpSpecBuilder.new(item.reload).call

      run = PipelineEngine.new(item.reload).call

      assert item.business
      assert_equal item.business, landing_page.reload.business
      assert_equal item.business, run.business
      assert_equal landing_page, run.aicoo_lab_landing_page
      assert run.stage_state("publish")["status"].in?(%w[done])
      assert run.metadata["pivot"]["decision"].present?
    end

    test "manual auto deploy does not start deploy" do
      business = businesses(:suelog)
      business.update!(auto_revision_mode: "automatic", auto_deploy_mode: "manual")
      create_deploy_ready_log(business)

      run = PipelineEngine.new(business).call

      assert_equal "waiting", run.stage_state("deploy")["status"]
      assert_equal "manual_deploy_mode", run.stage_state("deploy")["reason"]
      assert_equal "DeploySkipped", run.gate_snapshot.dig("deploy", "event")
    end

    test "approval auto deploy waits for deploy approval" do
      business = businesses(:suelog)
      business.update!(auto_revision_mode: "automatic", auto_deploy_mode: "approval")
      create_deploy_ready_log(business)

      run = PipelineEngine.new(business).call

      assert_equal "approval_waiting", run.stage_state("deploy")["status"]
      assert_equal "deploy_approval_required", run.stage_state("deploy")["reason"]
      assert_equal "DeployApprovalRequired", run.gate_snapshot.dig("deploy", "event")
    end

    test "automatic auto deploy starts when low risk tests and precheck pass" do
      business = businesses(:suelog)
      business.update!(auto_revision_mode: "automatic", auto_deploy_mode: "automatic")
      create_google_credential
      create_execution_profile(business)
      log = create_deploy_ready_log(business)

      run = PipelineEngine.new(business).call

      assert_equal "open", run.stage_state("deploy")["status"]
      assert_equal "automatic_deploy_ready", run.stage_state("deploy")["reason"]
      assert_equal "DeployStarted", run.gate_snapshot.dig("deploy", "event")
      assert_equal "abc123", log.reload.base_commit_sha
      assert_equal "DeployStarted", log.metadata["deploy_event"]
      assert_equal "started", log.deploy_result
    end

    test "automatic auto deploy falls back to approval when precheck fails" do
      business = businesses(:suelog)
      business.update!(auto_revision_mode: "automatic", auto_deploy_mode: "automatic")
      log = create_deploy_ready_log(business, tests_passed: false)

      run = PipelineEngine.new(business).call

      assert_equal "approval_waiting", run.stage_state("deploy")["status"]
      assert_equal "deploy_precheck_failed", run.stage_state("deploy")["reason"]
      assert_equal "DeployApprovalRequired", run.gate_snapshot.dig("deploy", "event")
      assert_equal "deploy_pending", log.reload.status
      assert log.metadata["deploy_precheck_errors"].present?
    end

    test "deploy succeeded and failed logs emit pipeline events" do
      business = businesses(:suelog)
      business.update!(auto_revision_mode: "automatic", auto_deploy_mode: "approval")
      create_deploy_ready_log(business).update!(deploy_result: "succeeded", status: "succeeded")

      succeeded_run = PipelineEngine.new(business).call
      assert_equal "done", succeeded_run.stage_state("deploy")["status"]
      assert_equal "DeploySucceeded", succeeded_run.gate_snapshot.dig("deploy", "event")

      business.auto_revision_run_logs.delete_all
      create_deploy_ready_log(business).update!(deploy_result: "failed", status: "failed")

      failed_run = PipelineEngine.new(business).call
      assert_equal "approval_waiting", failed_run.stage_state("deploy")["status"]
      assert_equal "DeployFailed", failed_run.gate_snapshot.dig("deploy", "event")
    end

    private

    def create_item
      IdeaPipelineItem.create!(
        title: "Pipeline Engine Idea",
        short_description: "Pipeline Engine検証",
        problem: "状態遷移が分散している",
        target_user: "事業オーナー",
        revenue_model: "月額",
        mvp_concept: "LPで反応を見る",
        lp_concept: "ベネフィット訴求",
        difficulty_score: 20,
        development_hours: 4,
        ai_implementation_score: 80
      )
    end

    def create_google_credential
      AicooGoogleCredential.create!(
        name: "Pipeline Test Google",
        client_id: "123-test.apps.googleusercontent.com",
        client_secret: "secret",
        google_cloud_project_id: "aicoo-test",
        refresh_token: "refresh"
      )
    end

    def create_execution_profile(business)
      business.create_business_execution_profile!(
        execution_type: "external_repo",
        repository_name: "suelog",
        repository_type: "rails",
        repository_path: Rails.root.to_s,
        github_repository: "owner/suelog",
        test_command: "bin/rails test",
        deploy_command: "bin/deploy",
        default_branch: "main",
        active: true
      )
    end

    def create_deploy_ready_log(business, tests_passed: true)
      AutoRevisionRunLog.create!(
        business:,
        status: "sent_to_codex",
        auto_revision_mode: business.auto_revision_mode,
        risk_level: "low",
        test_result: tests_passed ? "passed" : "failed",
        base_commit_sha: "abc123",
        message: "Deploy gate test",
        metadata: {
          "tests_passed" => tests_passed,
          "git_clean" => true,
          "target_branch" => "main"
        }
      )
    end
  end
end
