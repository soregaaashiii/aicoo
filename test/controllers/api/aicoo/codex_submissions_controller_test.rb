require "test_helper"

module Api
  module Aicoo
    class CodexSubmissionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @business = businesses(:suelog)
        profile = BusinessExecutionProfile.create!(
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
          title: "Codex callback test",
          status: "approved",
          action_type: "ui_improvement",
          immediate_value_yen: 10_000,
          success_probability: 0.5,
          expected_hours: 1,
          execution_prompt: "CTAを改善してください。"
        )
        task = AutoRevisionTask.from_action_candidate(candidate)
        task.approve!
        @submission = task.codex_submission
        @submission.update!(
          status: "submitted",
          prompt: task.codex_prompt_markdown,
          workspace_name: "AICOO",
          project_folder: "/workspace/suelog",
          repository_url: "https://github.com/example/suelog",
          base_branch: "main",
          working_branch: "aicoo/test"
        )
      end

      test "github tracking callback updates codex submission" do
        stub_env("AICOO_CODEX_CALLBACK_TOKEN" => "callback-token") do
          post "/api/aicoo/codex_submissions/#{@submission.id}/github_tracking",
               params: {
                 pull_request_url: "https://github.com/example/suelog/pull/22",
                 pr_status: "pr_created",
                 ci_status: "success",
                 merge_status: "未merge",
                 changed_files: [ "app/views/shops/show.html.erb" ]
               },
               headers: { "Authorization" => "Bearer callback-token" }
        end

        assert_response :success
        assert_equal "https://github.com/example/suelog/pull/22", @submission.reload.pr_url
        assert_equal "success", @submission.tracking_value(:ci_status)
        assert_includes @submission.response_payload["changed_files"], "app/views/shops/show.html.erb"
      end

      test "rejects invalid callback token" do
        stub_env("AICOO_CODEX_CALLBACK_TOKEN" => "callback-token") do
          post "/api/aicoo/codex_submissions/#{@submission.id}/github_tracking",
               params: { pull_request_url: "https://github.com/example/suelog/pull/22" },
               headers: { "Authorization" => "Bearer wrong" }
        end

        assert_response :unauthorized
      end

      private

      def stub_env(values)
        previous = values.keys.index_with { |key| ENV[key] }
        values.each { |key, value| ENV[key] = value }
        yield
      ensure
        previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      end
    end
  end
end
