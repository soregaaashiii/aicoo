require "test_helper"

module Aicoo
  class CodexActionQueueProcessorTest < ActiveSupport::TestCase
    setup do
      CodexSubmission.delete_all
      AutoRevisionExecution.delete_all
      AutoRevisionTask.delete_all
      AutoRevisionRunLog.delete_all
      AicooAutoRevisionSetting.delete_all
      ActionCandidate.update_all(status: "done")
      @business = businesses(:suelog)
      @business.business_execution_profile&.destroy!
      create_profile!
      AicooAutoRevisionSetting.current.resume_codex_queue!
    end

    test "processes only one task per call" do
      first = create_ready_task(title: "高期待値", final_expected_value_yen: 90_000)
      second = create_ready_task(title: "低期待値", final_expected_value_yen: 10_000)

      with_fake_github_issue_bridge do
        result = Aicoo::CodexActionQueueProcessor.new(force: true).call

        assert_equal true, result.started
        assert_equal first.id, result.task.id
        assert_equal "sent_to_codex", first.reload.status
        assert_equal "ready_for_codex", second.reload.status
        assert_equal 1, CodexSubmission.where(status: "submitted").count
      end
    end

    test "does not start when another task is active" do
      active = create_ready_task(title: "実行中", final_expected_value_yen: 100_000)
      active.update!(status: "sent_to_codex", sent_to_codex_at: Time.current)
      waiting = create_ready_task(title: "待機", final_expected_value_yen: 90_000)

      result = Aicoo::CodexActionQueueProcessor.new(force: true).call

      assert_equal false, result.started
      assert_equal "active_task_exists", result.reason
      assert_equal "ready_for_codex", waiting.reload.status
    end

    test "keeps waiting task when hourly limit is reached" do
      with_env("CODEX_MAX_STARTS_PER_HOUR" => "1") do
        previous = create_ready_task(title: "直前", final_expected_value_yen: 100_000)
        previous.update!(status: "sent_to_codex", sent_to_codex_at: 10.minutes.ago)
        previous.update!(status: "completed", finished_at: Time.current)
        waiting = create_ready_task(title: "待機", final_expected_value_yen: 90_000)

        result = Aicoo::CodexActionQueueProcessor.new(force: true).call

        assert_equal false, result.started
        assert_equal "hourly_limit_reached", result.reason
        assert_equal "ready_for_codex", waiting.reload.status
      end
    end

    test "keeps waiting task when daily limit is reached" do
      with_env("CODEX_MAX_STARTS_PER_DAY" => "1") do
        previous = create_ready_task(title: "本日実行済み", final_expected_value_yen: 100_000)
        previous.update!(status: "completed", sent_to_codex_at: 2.hours.ago, finished_at: Time.current)
        waiting = create_ready_task(title: "翌日待ち", final_expected_value_yen: 90_000)

        result = Aicoo::CodexActionQueueProcessor.new(force: true).call

        assert_equal false, result.started
        assert_equal "daily_limit_reached", result.reason
        assert_equal "ready_for_codex", waiting.reload.status
      end
    end

    test "pauses after consecutive failures" do
      3.times do |index|
        create_ready_task(title: "失敗 #{index}", final_expected_value_yen: 10_000 + index).update!(
          status: "failed",
          error_message: "同じ失敗"
        )
      end

      result = Aicoo::CodexActionQueueProcessor.new(force: true).call

      assert_equal false, result.started
      assert_equal "paused_by_consecutive_failures", result.reason
      assert AicooAutoRevisionSetting.current.reload.codex_queue_paused?
    end

    test "resume allows the next task to start" do
      setting = AicooAutoRevisionSetting.current
      setting.pause_codex_queue!(reason: "手動停止")
      task = create_ready_task(title: "再開後", final_expected_value_yen: 90_000)

      assert_equal "paused", Aicoo::CodexActionQueueProcessor.new(force: true).call.reason

      setting.resume_codex_queue!
      with_fake_github_issue_bridge do
        result = Aicoo::CodexActionQueueProcessor.new(force: true).call

        assert_equal true, result.started
        assert_equal task.id, result.task.id
      end
    end

    private

    def create_ready_task(title:, final_expected_value_yen:)
      candidate = @business.action_candidates.create!(
        title:,
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: final_expected_value_yen,
        final_expected_value_yen:,
        success_probability: 0.5,
        expected_hours: 1,
        execution_prompt: "#{title}を実装してください。"
      )
      candidate.update_columns(final_expected_value_yen:, success_probability: 0.5)
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

    def with_env(values)
      previous = values.transform_values { |_value| nil }
      values.each do |key, value|
        previous[key] = ENV[key]
        ENV[key] = value
      end
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
