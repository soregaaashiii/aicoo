require "test_helper"

module Aicoo
  class CodexGithubPrTrackerTest < ActiveSupport::TestCase
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
        title: "Codex PR Tracker",
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
      @submission.update!(
        repository_url: "https://github.com/example/suelog",
        response_payload: @submission.response_payload.to_h.merge(
          "github_issue_url" => "https://github.com/example/suelog/issues/7",
          "github_issue_number" => 7,
          "github_issue_repo" => "example/suelog"
        )
      )
    end

    test "detects pull request from github issue and stores tracking payload" do
      stub_env("AICOO_GITHUB_TOKEN" => "token") do
        tracker = Aicoo::CodexGithubPrTracker.new(@submission)
        fake_response = method(:fake_github_response)
        tracker.define_singleton_method(:get_json) { |path| fake_response.call(path) }

        result = tracker.call

        assert_equal "synced", result.status
        assert_equal "https://github.com/example/suelog/pull/12", result.pull_request_url
        @submission.reload
        assert_equal "https://github.com/example/suelog/pull/12", @submission.pr_url
        assert_equal "pr_created", @submission.tracking_value(:pr_status)
        assert_equal "approved", @submission.tracking_value(:review_status)
        assert_equal "success", @submission.tracking_value(:ci_status)
        assert_equal "未merge", @submission.tracking_value(:merge_status)
        assert_includes @submission.response_payload["changed_files"], "app/views/shops/show.html.erb"
      end
    end

    test "returns waiting status when github issue has no pull request url yet" do
      stub_env("AICOO_GITHUB_TOKEN" => "token") do
        tracker = Aicoo::CodexGithubPrTracker.new(@submission)
        tracker.define_singleton_method(:get_json) do |path|
          case path
          when "/repos/example/suelog/issues/7"
            { "body" => "Codex作業待ちです。" }
          when "/repos/example/suelog/issues/7/comments"
            []
          else
            flunk "unexpected github path: #{path}"
          end
        end

        result = tracker.call

        assert_equal "waiting_pr", result.status
        assert_nil result.pull_request_url
        assert_nil @submission.reload.pr_url
      end
    end

    private

    def fake_github_response(path)
      case path
      when "/repos/example/suelog/issues/7"
        { "body" => "Codex作業中です。" }
      when "/repos/example/suelog/issues/7/comments"
        [ { "body" => "PR https://github.com/example/suelog/pull/12 を作成しました。" } ]
      when "/repos/example/suelog/pulls/12"
        {
          "url" => "https://api.github.com/repos/example/suelog/pulls/12",
          "number" => 12,
          "state" => "open",
          "merged" => false,
          "draft" => false,
          "mergeable" => true,
          "head" => { "sha" => "abc123" },
          "base" => { "repo" => { "full_name" => "example/suelog" } }
        }
      when "/repos/example/suelog/pulls/12/files"
        [ { "filename" => "app/views/shops/show.html.erb" } ]
      when "/repos/example/suelog/commits/abc123/status"
        { "state" => "success" }
      else
        flunk "unexpected github path: #{path}"
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
