require "test_helper"

module Admin
  class CodexSubmissionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @business = businesses(:suelog)
      @profile = BusinessExecutionProfile.create!(
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
      candidate = ActionCandidate.create!(
        business: @business,
        title: "Codex Cloud送信テスト",
        status: "approved",
        action_type: "ui_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1,
        execution_prompt: "CTAを改善してください。"
      )
      @task = AutoRevisionTask.from_action_candidate(candidate)
      @task.approve!
      @task.update!(risk_level: "low")
      @submission = Aicoo::CodexSubmissionBuilder.new(@task).call.submission
    end

    test "index shows codex submissions" do
      get admin_codex_submissions_url

      assert_response :success
      assert_includes response.body, "Codex手動送信一覧"
      assert_includes response.body, @business.name
      assert_includes response.body, @submission.project_folder
      assert_includes response.body, @task.title
      assert_includes response.body, "Risk"
    end

    test "index filters by risk" do
      high_candidate = ActionCandidate.create!(
        business: @business,
        title: "高リスクCodex送信テスト",
        status: "approved",
        action_type: "ui_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1,
        execution_prompt: "migrationを含む変更を検討してください。"
      )
      high_task = AutoRevisionTask.from_action_candidate(high_candidate)
      high_task.update!(risk_level: "high")
      Aicoo::CodexSubmissionBuilder.new(high_task, force: true).call

      get admin_codex_submissions_url(risk: "low")

      assert_response :success
      assert_includes response.body, @task.title
      assert_not_includes response.body, high_task.title
    end

    test "show displays execution profile and prompt" do
      get admin_codex_submission_url(@submission)

      assert_response :success
      assert_includes response.body, "Codex手動送信詳細"
      assert_includes response.body, "Execution Profile"
      assert_includes response.body, "AutoRevisionTask"
      assert_includes response.body, "Response Payload"
      assert_includes response.body, @profile.codex_project_folder
      assert_includes response.body, "main直接pushは禁止"
    end

    test "marks submission as completed" do
      patch mark_completed_admin_codex_submission_url(@submission)

      assert_redirected_to admin_codex_submission_url(@submission)
      assert_equal "completed", @submission.reload.status
      assert_not_nil @submission.completed_at
    end

    test "updates pull request tracking" do
      patch update_tracking_admin_codex_submission_url(@submission), params: {
        codex_submission: {
          pull_request_url: "https://github.com/example/suelog/pull/12",
          pr_status: "pr_created",
          review_status: "pending",
          ci_status: "success",
          merge_status: "未merge",
          deploy_status: "未deploy"
        }
      }

      assert_redirected_to admin_codex_connection_url
      @submission.reload
      assert_equal "https://github.com/example/suelog/pull/12", @submission.pr_url
      assert_equal "success", @submission.tracking_value(:ci_status)
      assert_equal "pending", @submission.tracking_value(:review_status)
    end

    test "creates github issue for codex handoff" do
      result = Aicoo::CodexGithubIssueBridge::Result.new(
        created: true,
        issue_url: "https://github.com/example/suelog/issues/9",
        issue_number: 9,
        message: "GitHub Issue #9 を作成しました。",
        payload: {}
      )
      fake_bridge = Object.new
      fake_bridge.define_singleton_method(:call) { result }
      original_new = Aicoo::CodexGithubIssueBridge.method(:new)
      Aicoo::CodexGithubIssueBridge.define_singleton_method(:new) { |_submission| fake_bridge }

      post create_github_issue_admin_codex_submission_url(@submission)

      assert_redirected_to admin_codex_submission_url(@submission)
      assert_match "GitHub Issue #9", flash[:notice]
    ensure
      Aicoo::CodexGithubIssueBridge.define_singleton_method(:new) { |*args| original_new.call(*args) } if original_new
    end

    test "retries failed submission" do
      @submission.mark_failed!("Codex Cloud timeout")

      patch retry_admin_codex_submission_url(@submission)

      assert_redirected_to admin_codex_connection_url
      assert_equal "ready", @submission.reload.status
      assert_nil @submission.error_message
    end
  end
end
