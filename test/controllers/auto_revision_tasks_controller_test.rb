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
    assert_includes task.execution_prompt, "meta descriptionを改善してください。"
    assert_includes task.execution_prompt, "ActionCandidate実行指示書"
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
    assert_includes response.body, "Codex用プロンプトをコピー"
    assert_includes response.body, "承認する"
    assert_includes response.body, "Codex Quality Check"
    assert_includes response.body, "実装結果を登録"
    assert_includes response.body, "Target Repository"
    assert_includes response.body, "Execution Profileがmissing"
    assert_includes response.body, "Execution Profileを作成"
    assert_includes response.body, "Codex手動送信カード"
    assert_includes response.body, "Cloud Codexで開く（手動）"
    assert_includes response.body, "PR URLを登録"
  end

  test "shows configured execution profile on task detail" do
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      test_command: "bin/rails test",
      deploy_command: "bin/deploy"
    )
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    get auto_revision_task_url(task)

    assert_response :success
    assert_includes response.body, "Coverage Status"
    assert_includes response.body, "configured"
    assert_includes response.body, "kawamura/suelog"
    assert_includes response.body, "Auto Deploy Enabled"
    assert_includes response.body, "Auto Merge Enabled"
    assert_includes response.body, "Allowed Risk Level"
    assert_includes response.body, "Health Check URL"
    assert_not_includes response.body, "Execution Profileがmissing"
  end

  test "builds codex submission from task detail" do
    create_configured_codex_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!
    task.update!(risk_level: "low")

    assert_no_difference("CodexSubmission.count") do
      post build_codex_submission_auto_revision_task_url(task)
    end

    submission = task.reload.codex_submission
    assert_redirected_to auto_revision_task_url(task)
    assert_equal "ready", submission.status
    assert_equal "/workspace/suelog", submission.project_folder
    assert_includes submission.prompt, "main直接pushは禁止"
    assert_includes flash[:notice], "Codex手動送信用として準備しました"
  end

  test "marks codex submission as submitted" do
    create_configured_codex_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!
    task.update!(risk_level: "low")
    Aicoo::CodexSubmissionBuilder.new(task, force: true).call

    patch mark_codex_submission_submitted_auto_revision_task_url(task)

    submission = task.reload.codex_submission
    assert_redirected_to auto_revision_task_url(task)
    assert_equal "submitted", submission.status
    assert_not_nil submission.submitted_at
    assert_equal "sent_to_codex", task.status
  end

  test "records codex submission failure" do
    create_configured_codex_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!
    task.update!(risk_level: "low")
    Aicoo::CodexSubmissionBuilder.new(task, force: true).call

    patch mark_codex_submission_failed_auto_revision_task_url(task)

    submission = task.reload.codex_submission
    assert_redirected_to auto_revision_task_url(task)
    assert_equal "failed", submission.status
    assert_equal "Ownerが送信失敗として記録しました。", submission.error_message
  end

  test "exports codex prompt for valid task" do
    create_configured_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    assert_changes -> { task.reload.metadata["export_count"].to_i }, from: 0, to: 1 do
      get export_codex_prompt_auto_revision_task_url(task)
    end

    assert_response :success
    assert_includes response.body, "Codex Prompt Export"
    assert_includes response.body, "Markdown Export"
    assert_includes response.body, "AutoRevisionTask ##{task.id}"
    assert_includes response.body, "Target Repository Name: suelog"
    assert_includes response.body, "AICOO Result Intake Template"
  end

  test "downloads codex prompt markdown for valid task" do
    create_configured_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    get export_codex_prompt_auto_revision_task_url(task, download: "1")

    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_includes response.body, "AutoRevisionTask ##{task.id}"
    assert_includes response.body, "Changed Files:"
  end

  test "does not export codex prompt for invalid task" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    assert_no_changes -> { task.reload.metadata["export_count"].to_i } do
      get export_codex_prompt_auto_revision_task_url(task)
    end

    assert_response :unprocessable_content
    assert_includes response.body, "Target Validation"
    assert_includes response.body, "BusinessExecutionProfile"
    assert_includes response.body, "Execution Profileを作成"
  end

  test "approves auto revision task" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    patch approve_auto_revision_task_url(task)

    assert_redirected_to auto_revision_task_url(task)
    assert_equal "ready_for_codex", task.reload.status
    assert_not_nil task.approved_at
  end

  test "marks auto revision task as sent to codex" do
    create_configured_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!
    task.enqueue_for_codex!

    patch mark_sent_to_codex_auto_revision_task_url(task)

    assert_redirected_to codex_queue_auto_revision_tasks_url
    assert_equal "sent_to_codex", task.reload.status
    assert_not_nil task.sent_to_codex_at
  end

  test "does not mark invalid target task as sent to codex" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!

    patch mark_sent_to_codex_auto_revision_task_url(task)

    assert_redirected_to codex_queue_auto_revision_tasks_url
    assert_equal "ready_for_codex", task.reload.status
    assert_match(/Target Validationに失敗/, flash[:alert])
  end

  test "queues approved task for codex execution" do
    create_configured_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!

    assert_difference("AutoRevisionExecution.count", 1) do
      patch enqueue_auto_revision_task_url(task)
    end

    assert_redirected_to codex_queue_auto_revision_tasks_url
    assert_equal "queued", task.reload.status
    assert_equal "Auto Revision Taskを実行キューへ追加しました。", flash[:notice]
  end

  test "does not queue high risk task" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(execution_prompt: "認証tokenを扱うmigrationを追加してください。")
    task = AutoRevisionTask.from_action_candidate(candidate)
    task.approve!

    assert_no_difference("AutoRevisionExecution.count") do
      patch enqueue_auto_revision_task_url(task)
    end

    assert_redirected_to auto_revision_task_url(task)
    assert_equal "approved", task.reload.status
    assert_match(/high risk/, flash[:alert])
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
    task.auto_revision_executions.create!(status: "running", prompt_snapshot: task.codex_prompt_markdown)

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
          commit_sha: "abc123",
          pull_request_url: "https://github.com/example/repo/pull/1",
          deploy_url: "https://example.onrender.com",
          deploy_status: "deployed",
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
    execution = task.auto_revision_executions.last
    assert_equal "completed", execution.status
    assert_equal "abc123", execution.commit_sha
    assert_equal "https://github.com/example/repo/pull/1", execution.pull_request_url
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
    create_configured_profile
    ready = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    ready.approve!
    queued = create_task(title: "実行待ちタスク", status: "queued")
    sent = create_task(title: "Codex投入済みタスク", status: "sent_to_codex")
    running = create_task(title: "実装中タスク", status: "running")
    waiting = create_task(title: "承認待ちタスク", status: "waiting_approval")

    get codex_queue_auto_revision_tasks_url

    assert_response :success
    assert_includes response.body, "Codex Executor Queue"
    assert_includes response.body, ready.title
    assert_includes response.body, queued.title
    assert_includes response.body, sent.title
    assert_includes response.body, running.title
    assert_not_includes response.body, waiting.title
    assert_includes response.body, "Codex手動送信"
    assert_includes response.body, "実装開始"
    assert_includes response.body, "最終確認"
    assert_includes response.body, "Codexスレッド"
    assert_includes response.body, "Target"
    assert_includes response.body, "valid"
    assert_includes response.body, "プロンプト確認"
    assert_includes response.body, "プロンプトをコピー"
    assert_includes response.body, "詳細"
    assert_includes response.body, "手動送信済みにする"
    assert_includes response.body, "実行キューへ追加"
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

  def create_configured_profile
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      test_command: "bin/rails test",
      lint_command: "bundle exec rubocop",
      deploy_command: "bin/deploy"
    )
  end

  def create_configured_codex_profile
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "https://github.com/example/suelog",
      test_command: "bin/rails test",
      lint_command: "bundle exec rubocop",
      deploy_command: "bin/deploy",
      require_manual_approval: false,
      codex_enabled: true,
      codex_workspace_name: "AICOO",
      codex_project_folder: "/workspace/suelog",
      codex_repository_url: "https://github.com/example/suelog",
      codex_base_branch: "main",
      codex_working_branch_prefix: "aicoo/",
      codex_auto_submit_enabled: false,
      codex_auto_pr_enabled: true,
      codex_auto_merge_enabled: false,
      codex_auto_deploy_enabled: false,
      codex_risk_limit: "low"
    )
  end

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
