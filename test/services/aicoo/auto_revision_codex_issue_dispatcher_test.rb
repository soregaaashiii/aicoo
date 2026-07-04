require "test_helper"

module Aicoo
  class AutoRevisionCodexIssueDispatcherTest < ActiveSupport::TestCase
    setup do
      CodexSubmission.delete_all
      AutoRevisionExecution.delete_all
      AutoRevisionTask.delete_all
      AutoRevisionRunLog.delete_all
      @business = businesses(:suelog)
      @business.business_execution_profile&.destroy!
      create_profile!
      @task = create_ready_task
    end

    test "creates github issue for ready low risk task automatically" do
      with_fake_github_issue_bridge do
        result = Aicoo::AutoRevisionCodexIssueDispatcher.new.call(tasks: [ @task ], limit: 1)

        assert_equal 1, result.processed_count
        assert_equal 1, result.created_issue_count
        assert_equal 0, result.failed_count
        assert_equal "sent_to_codex", @task.reload.status
        assert_equal "submitted", @task.codex_submission.status
        assert_equal "https://github.com/example/suelog/issues/#{@task.id}", @task.codex_submission.github_issue_url
        assert_equal "created", result.details.first.fetch("status")
      end
    end

    test "skips when codex auto submit is off" do
      @business.business_execution_profile.update!(codex_auto_submit_enabled: false)

      result = Aicoo::AutoRevisionCodexIssueDispatcher.new.call(tasks: [ @task ], limit: 1)

      assert_equal 1, result.skipped_count
      assert_equal "codex_submission_not_ready", result.details.first.fetch("reason")
      assert_includes result.details.first.fetch("reasons"), "Auto SubmitがOFFです。"
      assert_nil @task.codex_submission&.github_issue_url
    end

    test "does not dispatch high risk task" do
      @task.update!(risk_level: "high")

      result = Aicoo::AutoRevisionCodexIssueDispatcher.new.call(tasks: [ @task ], limit: 1)

      assert_equal 0, result.processed_count
      assert_equal 0, result.created_issue_count
    end

    private

    def create_ready_task
      candidate = @business.action_candidates.create!(
        title: "SEOタイトル改善",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1,
        execution_prompt: "SEOタイトルを改善してください。"
      )
      AutoRevisionTask.from_action_candidate(candidate).tap do |task|
        task.update!(status: "ready_for_codex", risk_level: "low", approved_at: Time.current)
      end
    end

    def create_profile!
      @business.create_business_execution_profile!(
        repository_name: "suelog",
        repository_type: "rails",
        repository_path: "/apps/suelog",
        github_repository: "https://github.com/example/suelog",
        test_command: "bin/rails test",
        lint_command: "bin/rails zeitwerk:check",
        deploy_command: "bin/deploy",
        require_manual_approval: false,
        codex_enabled: true,
        codex_workspace_name: "AICOO",
        codex_project_folder: "/workspace/suelog",
        codex_repository_url: "https://github.com/example/suelog",
        codex_base_branch: "main",
        codex_working_branch_prefix: "aicoo/",
        codex_auto_submit_enabled: true,
        codex_risk_limit: "low"
      )
    end

    def with_fake_github_issue_bridge
      original_new = Aicoo::CodexGithubIssueBridge.method(:new)
      Aicoo::CodexGithubIssueBridge.define_singleton_method(:new) do |submission|
        fake_bridge = Object.new
        fake_bridge.define_singleton_method(:call) do
          issue_url = "https://github.com/example/suelog/issues/#{submission.auto_revision_task_id}"
          submission.mark_submitted!(
            payload: {
              "github_issue_url" => issue_url,
              "github_issue_number" => submission.auto_revision_task_id,
              "codex_handoff_mode" => "github_issue"
            }
          )
          Aicoo::CodexGithubIssueBridge::Result.new(
            created: true,
            issue_url:,
            issue_number: submission.auto_revision_task_id,
            message: "GitHub Issueを作成しました。",
            payload: submission.response_payload
          )
        end
        fake_bridge
      end

      yield
    ensure
      Aicoo::CodexGithubIssueBridge.define_singleton_method(:new) { |*args| original_new.call(*args) } if original_new
    end
  end
end
