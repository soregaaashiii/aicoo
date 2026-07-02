require "test_helper"

module Admin
  class CodexConnectionControllerTest < ActionDispatch::IntegrationTest
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
        production_url: "https://suelog.example.com",
        health_check_url: "https://suelog.example.com/up",
        codex_enabled: true,
        codex_workspace_name: "AICOO",
        codex_project_folder: "/workspace/suelog",
        codex_repository_url: "https://github.com/example/suelog",
        codex_base_branch: "main",
        codex_working_branch_prefix: "aicoo/",
        codex_auto_pr_enabled: true,
        codex_auto_merge_enabled: false,
        codex_auto_deploy_enabled: false
      )
    end

    test "show displays codex connection settings and diagnostics" do
      get admin_codex_connection_url

      assert_response :success
      assert_includes response.body, "Codex Cloud Connection Center"
      assert_includes response.body, "全体設定"
      assert_includes response.body, "Business別接続"
      assert_includes response.body, "Codexタスク"
      assert_includes response.body, "PR追跡"
      assert_includes response.body, "E2E診断"
      assert_includes response.body, @business.name
      assert_includes response.body, @profile.codex_repository_url
      assert_includes response.body, "repo設定あり"
      assert_includes response.body, "prompt生成可能"
    end
  end
end
