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
    assert_includes task.execution_prompt, "SEOタイトルを改善してください。"
    assert_includes task.execution_prompt, "ActionCandidate実行指示書"
    assert_includes task.execution_prompt, "Codexへ渡す修正文"
    assert_equal candidate.reload.final_score.to_d, task.priority_score
    assert_equal candidate.action_type, task.metadata["action_type"]
    assert_equal "low", task.risk_level
    assert_equal "waiting_approval", task.status
  end

  test "creates codex submission automatically when execution profile exists" do
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
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
      codex_auto_submit_enabled: false,
      codex_risk_limit: "low"
    )
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(execution_prompt: "SEOタイトルを改善してください。")

    task = AutoRevisionTask.from_action_candidate(candidate)

    assert task.codex_submission.present?
    assert_equal "draft", task.codex_submission.status
    assert_includes task.codex_submission.error_message, "Auto SubmitがOFFです。"
    assert_includes task.codex_submission.prompt, "Codex Cloud Submission"
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

  test "high risk approval stops at prompt only" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(execution_prompt: "認証tokenを扱うmigrationを追加してください。")
    task = AutoRevisionTask.from_action_candidate(candidate)

    task.approve!

    assert_equal "approved", task.status
    assert_not_nil task.approved_at
  end

  test "approved task can be queued for codex execution" do
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
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!

    assert_difference("AutoRevisionExecution.count", 1) do
      task.enqueue_for_codex!
    end

    execution = task.auto_revision_executions.last
    assert_equal "queued", task.status
    assert_equal "queued", execution.status
    assert_includes execution.prompt_snapshot, "AutoRevisionTask ##{task.id}"
    assert_equal "kawamura/suelog", execution.metadata["github_repository"]
    assert_equal "codex/auto-revision-#{task.id}", execution.metadata["working_branch"]
  end

  test "high risk task cannot be queued automatically" do
    candidate = action_candidates(:nagazakicho_article)
    candidate.update!(execution_prompt: "認証tokenを扱うmigrationを追加してください。")
    task = AutoRevisionTask.from_action_candidate(candidate)
    task.approve!

    assert_no_difference("AutoRevisionExecution.count") do
      assert_raises(ActiveRecord::RecordInvalid) { task.enqueue_for_codex! }
    end
  end

  test "can move through codex execution states" do
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
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.approve!
    task.enqueue_for_codex!

    task.mark_sent_to_codex!
    assert_equal "sent_to_codex", task.status
    assert_not_nil task.sent_to_codex_at

    task.start_implementation!
    assert_equal "running", task.status
    assert_not_nil task.started_at
    assert_not_nil task.started_running_at
    assert_equal "running", task.auto_revision_executions.last.status
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
    assert_includes prompt, "【共通ルール】"
    assert_includes prompt, "【サービス固有ルール】"
    assert_includes prompt, "【今回の依頼】"
    assert_includes prompt, "AicooActivityLogger.log"
    assert_includes prompt, "db:drop / db:reset / drop database は絶対に実行しない"
    assert_includes prompt, "既存機能を壊さない"
    assert_includes prompt, "本番secretやtokenを表示しない"
    assert_includes prompt, "bin/rails test"
    assert_includes prompt, "bin/rails zeitwerk:check"
    assert_includes prompt, "RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop"
    assert_includes prompt, "changed_files に変更ファイルを記録してください"
    assert_includes prompt, "test_result に確認コマンドの結果を記録してください"
    assert_includes prompt, "Working Branch: codex/auto-revision-#{task.id}"
    assert_includes prompt, "GitHub / PR / Deploy"
  end

  test "copies business execution profile target repository" do
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      github_repository: "kawamura/suelog",
      test_command: "bin/rails test",
      lint_command: "bundle exec rubocop",
      forbidden_patterns: "db:drop\ndelete_all"
    )

    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    assert_equal businesses(:suelog), task.target_business
    assert_equal "suelog", task.target_repository_name
    assert_equal "rails", task.target_repository_type
    assert_equal "suelog", task.target_repository_display
  end

  test "codex prompt includes business execution profile" do
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      working_branch_prefix: "codex/suelog",
      test_command: "bin/rails test:system",
      lint_command: "bundle exec standardrb",
      deploy_command: "bin/deploy",
      render_service_name: "suelog-web",
      auto_deploy_enabled: true,
      auto_merge_enabled: true,
      auto_deploy_risk_limit: "medium",
      require_manual_approval: false,
      production_url: "https://suelog.example.com",
      health_check_url: "https://suelog.example.com/health",
      codex_instructions: "吸えログ固有のSEO導線を壊さない。",
      forbidden_patterns: "db:drop\ndestroy_all"
    )

    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    prompt = task.codex_prompt

    assert_includes prompt, "対象リポジトリ: suelog"
    assert_includes prompt, "リポジトリ種別: rails"
    assert_includes prompt, "GitHub Repository: kawamura/suelog"
    assert_includes prompt, "Repository Path: /apps/suelog"
    assert_includes prompt, "Working Branch: codex/suelog-#{task.id}"
    assert_includes prompt, "Render Service: suelog-web"
    assert_includes prompt, "Auto Merge Enabled: true"
    assert_includes prompt, "Auto Deploy Enabled: true"
    assert_includes prompt, "Auto Deploy Risk Limit: medium"
    assert_includes prompt, "Health Check URL: https://suelog.example.com/health"
    assert_includes prompt, "main直接push禁止"
    assert_includes prompt, "吸えログ固有のSEO導線を壊さない。"
    assert_includes prompt, "bin/rails test:system"
    assert_includes prompt, "bundle exec standardrb"
    assert_includes prompt, "destroy_all"
  end

  test "high risk prompt forbids auto merge and auto deploy even when profile allows deploy" do
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      test_command: "bin/rails test",
      deploy_command: "bin/deploy",
      auto_deploy_enabled: true,
      auto_merge_enabled: true,
      auto_deploy_risk_limit: "high",
      require_manual_approval: false
    )
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.update!(risk_level: "high")

    prompt = task.codex_prompt

    assert_not task.auto_deploy_allowed?
    assert_includes prompt, "high riskの場合は自動merge・自動デプロイ禁止"
    assert_includes prompt, "高リスクのためプロンプト生成のみ"
  end

  test "codex prompt markdown includes export metadata and result intake template" do
    BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      default_branch: "main",
      test_command: "bin/rails test",
      lint_command: "bundle exec rubocop",
      deploy_command: "bin/deploy",
      codex_instructions: "吸えログ固有の注意事項",
      forbidden_patterns: "db:drop\ndestroy_all"
    )
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    markdown = task.codex_prompt_markdown

    assert_includes markdown, "AutoRevisionTask ##{task.id}"
    assert_includes markdown, "Target Repository Name: suelog"
    assert_includes markdown, "Target Repository Type: rails"
    assert_includes markdown, "GitHub Repository: kawamura/suelog"
    assert_includes markdown, "Repository Path: /apps/suelog"
    assert_includes markdown, "Default Branch: main"
    assert_includes markdown, "Working Branch: codex/auto-revision-#{task.id}"
    assert_includes markdown, "GitHub / PR / Deploy Flow"
    assert_includes markdown, "auto_deploy_enabled=false の場合はPR作成までで停止"
    assert_includes markdown, "吸えログ固有の注意事項"
    assert_includes markdown, "destroy_all"
    assert_includes markdown, "AICOO Result Intake Template"
    assert_includes markdown, "Changed Files:"
    assert_includes markdown, "Test Result:"
  end

  test "records codex prompt export history" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    task.record_codex_prompt_export!
    task.record_codex_prompt_export!

    assert_equal 2, task.metadata["export_count"]
    assert task.metadata["last_exported_at"].present?
  end

  test "records succeeded result with finished_at" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.auto_revision_executions.create!(status: "running", prompt_snapshot: task.codex_prompt_markdown)

    task.record_result!(
      status: "succeeded",
      result_summary: "実装完了",
      changed_files: "app/models/example.rb",
      test_result: "0 failures",
      codex_output: "done",
      commit_sha: "abc123",
      pull_request_url: "https://github.com/example/repo/pull/1",
      deploy_url: "https://aicoo.onrender.com",
      deploy_status: "deployed"
    )

    assert_equal "succeeded", task.status
    assert_equal "実装完了", task.result_summary
    assert_equal "app/models/example.rb", task.changed_files
    assert_equal "0 failures", task.test_result
    assert_equal "done", task.codex_output
    assert_not_nil task.finished_at
    assert_equal "passed", task.codex_quality_check.result
    execution = task.auto_revision_executions.last
    assert_equal "completed", execution.status
    assert_equal "abc123", execution.commit_sha
    assert_equal "https://github.com/example/repo/pull/1", execution.pull_request_url
    assert_equal "deployed", execution.deploy_status
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
    assert_equal true, log.metadata["learning_loop_verified"]
    assert_equal "approved", log.metadata["codex_quality_approval_status"]
  end

  test "unapproved quality gate is not learning loop verified" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.record_result!(
      status: "partial_succeeded",
      result_summary: "要確認",
      changed_files: "db/migrate/20260623000000_add_column.rb\nconfig/credentials.yml.enc",
      test_result: ""
    )

    assert_difference("ActionExecutionLog.count", 1) do
      task.create_action_execution_log!
    end

    log = ActionExecutionLog.last
    assert_equal "pending", task.codex_quality_check.approval_status
    assert_equal true, log.metadata["quality_review_required"]
    assert_equal false, log.metadata["learning_loop_verified"]
  end
end
