require "test_helper"

module Aicoo
  class CodexResultImporterTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      BusinessExecutionProfile.create!(
        business: @business,
        repository_name: "suelog",
        repository_type: "rails",
        repository_path: "/apps/suelog",
        github_repository: "https://github.com/example/suelog",
        test_command: "bin/rails test",
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
      candidate = @business.action_candidates.create!(
        title: "Codex result import test",
        status: "approved",
        action_type: "ui_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1,
        execution_prompt: "CTAを改善してください。"
      )
      @task = AutoRevisionTask.from_action_candidate(candidate)
      @task.approve!
      @submission = CodexSubmissionBuilder.new(@task).call.submission
    end

    test "imports codex result into task action result activity and learning queue" do
      assert_difference -> { ActionExecutionLog.count }, 1 do
        assert_difference -> { ActionResult.count }, 1 do
          assert_difference -> { BusinessActivityLog.where(activity_type: "codex_revision_imported").count }, 1 do
            CodexResultImporter.new(
              @submission,
              result_summary: "CTAと比較表を追加しました。",
              changed_files: "app/views/articles/show.html.erb",
              test_result: "bin/rails test 0 failures",
              pull_request_url: "https://github.com/example/suelog/pull/44",
              commit_sha: "abc123",
              deploy_status: "deployed",
              actual_profit_yen: 0
            ).call
          end
        end
      end

      @task.reload
      @submission.reload
      result = @task.action_candidate.action_result

      assert_equal "completed", @task.status
      assert_equal "completed", @submission.status
      assert_equal "pending", result.evaluation_status
      assert_includes result.note, "CTAと比較表を追加しました。"
      assert_equal "done", @task.action_candidate.reload.status
      assert_equal "https://github.com/example/suelog/pull/44", @submission.pr_url
      assert_equal "https://github.com/example/suelog/pull/44", @task.auto_revision_executions.last.pull_request_url
      assert_equal "deployed", @task.auto_revision_executions.last.deploy_status
    end

    test "requires result summary" do
      error = assert_raises(ArgumentError) do
        CodexResultImporter.new(@submission, result_summary: "").call
      end

      assert_includes error.message, "実装内容"
    end
  end
end
