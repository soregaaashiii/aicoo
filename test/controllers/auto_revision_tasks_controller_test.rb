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
    assert_includes response.body, "承認"
    assert_includes response.body, "実装結果を登録"
  end

  test "approves auto revision task" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    patch approve_auto_revision_task_url(task)

    assert_redirected_to auto_revision_task_url(task)
    assert_equal "approved", task.reload.status
    assert_not_nil task.approved_at
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
end
