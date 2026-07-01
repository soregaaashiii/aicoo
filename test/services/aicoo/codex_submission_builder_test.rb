require "test_helper"

module Aicoo
  class CodexSubmissionBuilderTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @candidate = ActionCandidate.create!(
        business: @business,
        title: "吸えログのCV導線を改善する",
        status: "approved",
        action_type: "ui_improvement",
        immediate_value_yen: 20_000,
        success_probability: 0.4,
        expected_hours: 1,
        execution_prompt: "電話・地図・予約導線を改善してください。"
      )
      @task = AutoRevisionTask.from_action_candidate(@candidate)
      @task.approve!
      @task.update!(risk_level: "low")
    end

    test "creates ready codex submission when profile allows codex cloud" do
      create_profile!(
        codex_enabled: true,
        codex_auto_submit_enabled: true,
        require_manual_approval: false
      )

      result = CodexSubmissionBuilder.new(@task).call

      assert result.ready
      assert_equal "ready", result.submission.status
      assert_equal @business, result.submission.business
      assert_equal "/workspace/suelog", result.submission.project_folder
      assert_equal "https://github.com/example/suelog", result.submission.repository_url
      assert_equal "main", result.submission.base_branch
      assert_match(/\Aaicoo\//, result.submission.working_branch)
      assert_includes result.submission.prompt, "main直接pushは禁止"
      assert_includes result.submission.prompt, "作業ブランチからPRを作成してください"
      assert_includes result.submission.prompt, "電話・地図・予約導線を改善してください。"
    end

    test "keeps draft when codex is disabled" do
      create_profile!(codex_enabled: false, codex_auto_submit_enabled: true)

      result = CodexSubmissionBuilder.new(@task, force: true).call

      assert_not result.ready
      assert_equal "draft", result.submission.status
      assert_includes result.reasons, "Codex連携がOFFです。"
      assert_includes result.submission.error_message, "Codex連携がOFFです。"
    end

    test "keeps draft when required codex project fields are missing" do
      create_profile!(
        codex_enabled: true,
        codex_project_folder: nil,
        codex_repository_url: nil,
        github_repository: nil
      )

      result = CodexSubmissionBuilder.new(@task, force: true).call

      assert_equal "draft", result.submission.status
      assert_includes result.reasons, "Codex作業フォルダが未設定です。"
      assert_includes result.reasons, "Repository URLが未設定です。"
    end

    test "keeps draft when risk exceeds profile limit" do
      create_profile!(codex_enabled: true, codex_risk_limit: "low")
      @task.update!(risk_level: "medium")

      result = CodexSubmissionBuilder.new(@task, force: true).call

      assert_equal "draft", result.submission.status
      assert_includes result.reasons, "risk medium がCodex Risk Limit lowを超えています。"
    end

    test "force build bypasses auto submit off but not safety reasons" do
      create_profile!(codex_enabled: true, codex_auto_submit_enabled: false)

      result = CodexSubmissionBuilder.new(@task, force: true).call

      assert result.ready
      assert_equal "ready", result.submission.status
      assert_empty result.reasons
    end

    private

    def create_profile!(attributes = {})
      BusinessExecutionProfile.create!(
        {
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
          codex_auto_pr_enabled: true,
          codex_auto_merge_enabled: false,
          codex_auto_deploy_enabled: false,
          codex_risk_limit: "low"
        }.merge(attributes)
      )
    end
  end
end
