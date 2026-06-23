require "test_helper"

class AutoRevisionTasksControllerTest < ActionDispatch::IntegrationTest
  test "creates auto revision task from action candidate" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(execution_prompt: "meta descriptionを改善してください。")

    assert_difference("AutoRevisionTask.count", 1) do
      post auto_revision_tasks_url(action_candidate_id: candidate.id)
    end

    task = AutoRevisionTask.last
    assert_redirected_to auto_revision_task_url(task)
    assert_equal candidate, task.action_candidate
    assert_equal "meta descriptionを改善してください。", task.execution_prompt
  end

  test "does not duplicate active task for same action candidate" do
    candidate = action_candidates(:nagazakicho_article)
    existing = AutoRevisionTask.from_action_candidate(candidate)

    assert_no_difference("AutoRevisionTask.count") do
      post auto_revision_tasks_url(action_candidate_id: candidate.id)
    end

    assert_redirected_to auto_revision_task_url(existing)
  end

  test "shows auto revision task detail with codex prompt" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    get auto_revision_task_url(task)

    assert_response :success
    assert_includes response.body, "Codex用プロンプト"
    assert_includes response.body, "db:drop / db:reset / drop database は絶対に実行しない"
    assert_includes response.body, "bin/rails test"
    assert_includes response.body, "Codexプロンプトをコピー"
    assert_includes response.body, "承認"
    assert_includes response.body, "Codex Quality Check"
    assert_includes response.body, "実装結果を登録"
  end

  test "approves auto revision task" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    patch approve_auto_revision_task_url(task)

    assert_redirected_to auto_revision_task_url(task)
    assert_equal "ready_for_codex", task.reload.status
    assert_not_nil task.approved_at
  end

  test "marks auto revision task as sent to codex" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!

    patch mark_sent_to_codex_auto_revision_task_url(task)

    assert_redirected_to codex_queue_auto_revision_tasks_url
    assert_equal "sent_to_codex", task.reload.status
    assert_not_nil task.sent_to_codex_at
  end

  test "starts implementation" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.update!(status: "sent_to_codex")

    patch start_implementation_auto_revision_task_url(task)

    assert_redirected_to codex_queue_auto_revision_tasks_url
    assert_equal "running", task.reload.status
    assert_not_nil task.started_at
    assert_not_nil task.started_running_at
  end

  test "updates codex tracking fields" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    patch update_codex_tracking_auto_revision_task_url(task), params: {
      auto_revision_task: {
        codex_thread_url: "https://chatgpt.com/codex/thread-1",
        codex_session_label: "SUELOG-SEO-001",
        last_checked_at: "2026-06-23T10:00"
      }
    }

    assert_redirected_to auto_revision_task_url(task)
    task.reload
    assert_equal "https://chatgpt.com/codex/thread-1", task.codex_thread_url
    assert_equal "SUELOG-SEO-001", task.codex_session_label
    assert_not_nil task.last_checked_at
  end

  test "updates last checked at to now" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    patch update_codex_tracking_auto_revision_task_url(task), params: {
      mark_checked: "1",
      auto_revision_task: {
        codex_thread_url: "",
        codex_session_label: "",
        last_checked_at: ""
      }
    }

    assert_redirected_to auto_revision_task_url(task)
    assert_not_nil task.reload.last_checked_at
  end

  test "cancels auto revision task" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    patch cancel_auto_revision_task_url(task)

    assert_redirected_to auto_revision_tasks_url
    assert_equal "canceled", task.reload.status
    assert_not_nil task.finished_at
  end

  test "records succeeded result and creates action execution log" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    assert_difference("ActionExecutionLog.count", 1) do
      patch record_result_auto_revision_task_url(task), params: {
        create_action_execution_log: "1",
        auto_revision_task: {
          status: "succeeded",
          result_summary: "実装しました",
          error_message: "",
          changed_files: "app/views/example.html.erb",
          test_result: "bin/rails test passed",
          codex_output: "done",
          finished_at: Time.current.strftime("%Y-%m-%dT%H:%M")
        }
      }
    end

    assert_redirected_to auto_revision_task_url(task)
    task.reload
    assert_equal "succeeded", task.status
    assert_equal "実装しました", task.result_summary
    assert_equal "app/views/example.html.erb", task.changed_files
    assert_equal "passed", task.codex_quality_check.result
    assert_equal "completed", ActionExecutionLog.last.status
  end

  test "records failed result with error message" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    patch record_result_auto_revision_task_url(task), params: {
      auto_revision_task: {
        status: "failed",
        result_summary: "途中で失敗",
        error_message: "spec failed",
        changed_files: "",
        test_result: "failed",
        codex_output: "error",
        finished_at: Time.current.strftime("%Y-%m-%dT%H:%M")
      }
    }

    assert_redirected_to auto_revision_task_url(task)
    assert_equal "failed", task.reload.status
    assert_equal "spec failed", task.error_message
  end

  test "index shows task summary rows" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    get auto_revision_tasks_url

    assert_response :success
    assert_includes response.body, "Auto Revision Tasks"
    assert_includes response.body, task.title
  end

  test "codex queue shows only executable queue statuses" do
    ready = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    ready.approve!
    sent = create_task(title: "Codex投入済みタスク", status: "sent_to_codex")
    running = create_task(title: "実装中タスク", status: "running")
    waiting = create_task(title: "承認待ちタスク", status: "waiting_approval")

    get codex_queue_auto_revision_tasks_url

    assert_response :success
    assert_includes response.body, "Codex Executor Queue"
    assert_includes response.body, ready.title
    assert_includes response.body, sent.title
    assert_includes response.body, running.title
    assert_not_includes response.body, waiting.title
    assert_includes response.body, "Codex投入"
    assert_includes response.body, "実装開始"
    assert_includes response.body, "最終確認"
    assert_includes response.body, "Codexスレッド"
    assert_includes response.body, "Codex投入済みにする"
    assert_includes response.body, "実装開始"
    assert_includes response.body, "結果登録"
  end

  test "codex queue can filter stale tasks" do
    stale = create_task(title: "放置Codexタスク", status: "running")
    stale.update!(started_running_at: 8.days.ago, last_checked_at: nil)
    fresh = create_task(title: "新しいCodexタスク", status: "running")
    fresh.update!(started_running_at: Time.current, last_checked_at: Time.current)

    get codex_queue_auto_revision_tasks_url(status: "stale")

    assert_response :success
    assert_includes response.body, stale.title
    assert_not_includes response.body, fresh.title
    assert_includes response.body, "stale"
  end

  private

  def create_task(title:, status:)
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title:,
      action_type: "seo_improvement",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1,
      execution_prompt: "SEOタイトルを改善してください。"
    )
    AutoRevisionTask.from_action_candidate(candidate).tap { |task| task.update!(status:) }
  end
end
