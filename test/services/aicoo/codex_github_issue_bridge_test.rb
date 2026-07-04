require "test_helper"

module Aicoo
  class CodexGithubIssueBridgeTest < ActiveSupport::TestCase
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
      candidate = @business.action_candidates.create!(
        title: "Codex Issue Bridge",
        status: "approved",
        action_type: "ui_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1,
        execution_prompt: "CTAを改善してください。"
      )
      task = AutoRevisionTask.from_action_candidate(candidate)
      task.approve!
      @submission = Aicoo::CodexSubmissionBuilder.new(task).call.submission
      @submission.update!(repository_url: "https://github.com/example/suelog")
    end

    test "creates github issue and marks submission submitted" do
      stub_env("AICOO_GITHUB_TOKEN" => "token") do
        bridge = Aicoo::CodexGithubIssueBridge.new(@submission)
        response = success_response
        bridge.define_singleton_method(:post_issue!) { response }
        result = bridge.call

        assert result.created
        assert_equal "https://github.com/example/suelog/issues/7", result.issue_url
        assert_equal "submitted", @submission.reload.status
        assert_equal "https://github.com/example/suelog/issues/7", @submission.github_issue_url
        assert_equal 7, @submission.github_issue_number
        assert_includes @submission.response_payload["codex_handoff_mode"], "github_issue"
        assert_equal "sent_to_codex", @submission.auto_revision_task.reload.status
        assert_not_nil @submission.auto_revision_task.sent_to_codex_at
      end
    end

    test "fails clearly when github token is missing" do
      @submission.update!(repository_url: "https://github.com/example/suelog")

      error = assert_raises(ArgumentError) do
        Aicoo::CodexGithubIssueBridge.new(@submission).call
      end

      assert_includes error.message, "GITHUB_TOKEN"
    end

    private

    def success_response
      Net::HTTPCreated.new("1.1", "201", "Created").tap do |response|
        body = {
          html_url: "https://github.com/example/suelog/issues/7",
          number: 7,
          url: "https://api.github.com/repos/example/suelog/issues/7"
        }.to_json
        response.define_singleton_method(:body) { body }
      end
    end

    def stub_env(values)
      previous = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
