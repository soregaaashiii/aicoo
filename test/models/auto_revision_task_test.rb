require "test_helper"

class AutoRevisionTaskTest < ActiveSupport::TestCase
  test "creates task from action candidate" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(
      execution_prompt: "SEOタイトルを改善してください。",
      final_score: 12_345,
      evaluation_reason: "CTR改善余地があります。"
    )

    task = AutoRevisionTask.from_action_candidate(candidate)

    assert_equal candidate, task.action_candidate
    assert_equal candidate.business, task.business
    assert_equal candidate.title, task.title
    assert_equal "SEOタイトルを改善してください。", task.execution_prompt
    assert_equal candidate.reload.final_score.to_d, task.priority_score
    assert_equal candidate.action_type, task.metadata["action_type"]
    assert_equal "low", task.risk_level
    assert_equal "waiting_approval", task.status
  end

  test "detects high risk from migration and credentials" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(
      title: "認証credentialを変更する",
      execution_prompt: "DB migrationを追加し、tokenを扱う設定を変更してください。"
    )

    assert_equal "high", AutoRevisionTask.risk_level_for(candidate)
  end

  test "high risk is not automatically approved" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(execution_prompt: "DB migrationを追加してください。")

    task = AutoRevisionTask.from_action_candidate(candidate)

    assert_equal "high", task.risk_level
    assert_equal "waiting_approval", task.status
    assert_nil task.approved_at
  end

  test "low risk can be approved" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(execution_prompt: "表示文言を改善してください。")
    task = AutoRevisionTask.from_action_candidate(candidate)

    task.approve!

    assert_equal "ready_for_codex", task.status
    assert_not_nil task.approved_at
  end

  test "can move through codex execution states" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!

    task.mark_sent_to_codex!
    assert_equal "sent_to_codex", task.status
    assert_not_nil task.sent_to_codex_at

    task.start_implementation!
    assert_equal "running", task.status
    assert_not_nil task.started_at
    assert_not_nil task.started_running_at
  end

  test "detects stale codex task" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.update!(
      status: "running",
      started_running_at: 8.days.ago,
      last_checked_at: nil
    )

    assert task.stale_codex_task?

    task.update!(last_checked_at: Time.current)
    assert_not task.stale_codex_task?
  end

  test "codex prompt includes safety rules and commands" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    prompt = task.codex_prompt

    assert_includes prompt, "タスクID: AutoRevisionTask ##{task.id}"
    assert_includes prompt, "db:drop / db:reset / drop database は絶対に実行しない"
    assert_includes prompt, "既存機能を壊さない"
    assert_includes prompt, "本番secretやtokenを表示しない"
    assert_includes prompt, "bin/rails test"
    assert_includes prompt, "bin/rails zeitwerk:check"
    assert_includes prompt, "RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop"
    assert_includes prompt, "changed_files に変更ファイルを記録してください"
    assert_includes prompt, "test_result に確認コマンドの結果を記録してください"
  end

  test "records succeeded result with finished_at" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    task.record_result!(
      status: "succeeded",
      result_summary: "実装完了",
      changed_files: "app/models/example.rb",
      test_result: "0 failures",
      codex_output: "done"
    )

    assert_equal "succeeded", task.status
    assert_equal "実装完了", task.result_summary
    assert_equal "app/models/example.rb", task.changed_files
    assert_equal "0 failures", task.test_result
    assert_equal "done", task.codex_output
    assert_not_nil task.finished_at
    assert_equal "passed", task.codex_quality_check.result
  end

  test "partial succeeded status is valid" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    task.update!(status: "partial_succeeded", result_summary: "一部だけ完了")

    assert_equal "partial_succeeded", task.status
  end

  test "records failed result with error message" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    task.record_result!(status: "failed", result_summary: "失敗", error_message: "test failed")

    assert_equal "failed", task.status
    assert_equal "test failed", task.error_message
  end

  test "creates action execution log from result" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.record_result!(
      status: "partial_succeeded",
      result_summary: "半分だけ実装",
      error_message: "一部未対応",
      changed_files: "app/views/example.html.erb",
      test_result: "0 failures"
    )

    assert_difference("ActionExecutionLog.count", 1) do
      task.create_action_execution_log!
    end

    log = ActionExecutionLog.last
    assert_equal task.action_candidate, log.action_candidate
    assert_equal "partial", log.status
    assert_equal "半分だけ実装", log.actual_action
    assert_equal task.id, log.metadata["auto_revision_task_id"]
    assert_equal task.codex_quality_check.id, log.metadata["codex_quality_check_id"]
    assert_equal false, log.metadata["quality_review_required"]
  end
end
