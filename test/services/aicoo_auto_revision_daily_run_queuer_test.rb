require "test_helper"

class AicooAutoRevisionDailyRunQueuerTest < ActiveSupport::TestCase
  setup do
    AutoRevisionRunLog.delete_all
    AutoRevisionQueueRun.delete_all
    CodexSubmission.delete_all
    AutoRevisionExecution.delete_all
    AutoRevisionTask.delete_all
    AicooAutoRevisionSetting.delete_all
    ActionCandidate.update_all(status: "done")
    Business.update_all(auto_revision_mode: "manual")
    businesses(:suelog).business_execution_profile&.destroy!
  end

  test "does not run when setting is disabled" do
    AicooAutoRevisionSetting.current.update!(enabled: false)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal false, result.ran
    assert_equal "disabled", result.reason
    assert_equal 0, AutoRevisionQueueRun.count
    assert_equal 0, AutoRevisionTask.count
  end

  test "runs when enabled and creates queue run" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal true, result.ran
    assert_equal 1, AutoRevisionTask.count
    assert_equal 1, AutoRevisionQueueRun.count
    assert_equal daily_run, result.queue_run.aicoo_daily_run
    assert_equal 1, result.queue_run.generated_tasks_count
    assert AicooAutoRevisionSetting.current.last_auto_queue_at.present?
  end

  test "runs for partial failed daily run after completed generation steps" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run(status: "partial_failed")
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal true, result.ran
    assert_equal 1, result.queue_run.generated_tasks_count
    assert_equal daily_run, result.queue_run.aicoo_daily_run
  end

  test "queues all eligible tasks without using dispatch start limit" do
    AicooAutoRevisionSetting.current.update!(enabled: true, max_tasks_per_run: 2)
    daily_run = create_daily_run
    4.times { |index| create_candidate(title: "SEOタイトル改善 #{index}", execution_prompt: "SEOタイトルを改善してください。") }

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 4, result.queue_run.generated_tasks_count
    assert_equal 4, AutoRevisionTask.count
    assert_equal "none", result.queue_run.metadata.fetch("queue_registration_limit")
  end

  test "respects minimum final score" do
    AicooAutoRevisionSetting.current.update!(enabled: true, minimum_final_score: 99_999)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 0, result.queue_run.generated_tasks_count
    assert_equal 0, AutoRevisionTask.count
    assert_equal "all_candidates_skipped", result.queue_run.metadata.fetch("reason")
    assert_includes result.queue_run.metadata.fetch("message"), "スコア不足"
    assert_includes result.queue_run.metadata.fetch("message"), "診断"
    assert_equal 1, result.queue_run.metadata.dig("diagnostics", "below_minimum_final_score_count")
    assert_equal "below_minimum_final_score", result.queue_run.metadata.fetch("skipped_reasons").first.fetch("reason")
  end

  test "does not queue candidate without execution readiness even when auto revision is enabled" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    candidate = create_candidate(
      title: "滞在時間が短いページを改善する",
      execution_prompt: "滞在時間が短いページを改善してください。"
    )
    candidate.update_columns(
      action_type: "seo_improvement",
      execution_prompt: "滞在時間が短いページを改善してください。",
      metadata: {
        "codex_eligible" => true,
        "auto_revision" => true,
        "concrete_task" => "滞在時間が短いページを改善する"
      },
      updated_at: Time.current
    )

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 0, result.queue_run.generated_tasks_count
    assert_equal 0, AutoRevisionTask.count
    assert_equal "all_candidates_skipped", result.queue_run.metadata.fetch("reason")
    assert_match(/execution_readiness:/, result.queue_run.metadata.fetch("skipped_reasons").first.fetch("reason"))
  end

  test "queues ready candidate when auto revision is enabled" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    create_candidate(title: "梅田 喫煙 カフェのtitleを改善する", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 1, result.queue_run.generated_tasks_count
    assert_equal 1, AutoRevisionTask.count
  end

  test "reports high risk candidates and keeps them as manual proposals" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    create_candidate(title: "DB migrationで認証tokenを変更", execution_prompt: "DB migrationでcredentialを変更してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 1, result.queue_run.generated_tasks_count
    assert_equal 1, result.queue_run.high_risk_candidates_count
    assert_equal 1, AutoRevisionTask.count
    assert_equal [ AutoRevisionRunLog.last.id ], result.queue_run.metadata["auto_revision_run_log_ids"]
  end

  test "does not create twice for same daily run" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    first_result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_no_difference("AutoRevisionTask.count") do
      second_result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)
      assert_equal false, second_result.ran
      assert_equal "already_run", second_result.reason
      assert_equal first_result.queue_run, second_result.queue_run
    end
  end

  test "does not dispatch ready codex tasks during daily run queueing" do
    AicooAutoRevisionSetting.current.update!(enabled: true, max_tasks_per_run: 2)
    daily_run = create_daily_run
    task = create_ready_codex_task

    with_fake_github_issue_bridge do
      result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

      assert_equal true, result.ran
      assert_equal 0, result.queue_run.metadata.fetch("codex_issue_processed_count")
      assert_equal 0, result.queue_run.metadata.fetch("codex_issue_created_count")
      assert_equal "separated_to_codex_action_queue_processor", result.queue_run.metadata.fetch("codex_issue_dispatch")
      assert_equal "ready_for_codex", task.reload.status
      assert_nil task.codex_submission.github_issue_url
    end
  end

  private

  def create_daily_run(status: "success")
    AicooDailyRun.create!(target_date: Date.yesterday, status:, source: "manual", started_at: Time.current)
  end

  def create_candidate(title:, execution_prompt:)
    ActionCandidate.create!(
      business: businesses(:suelog),
      title:,
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 20_000,
      success_probability: 1,
      expected_hours: 1,
      execution_prompt:,
      metadata: ready_codex_metadata
    )
  end

  def ready_codex_metadata
    {
      "target_url" => "/",
      "target_query" => "梅田 喫煙 カフェ",
      "concrete_task" => "SEOタイトルとmeta descriptionを改善する",
      "target_files" => [ "app/views/articles/show.html.erb" ],
      "completion_criteria" => [ "SEOタイトルが変更されていること" ],
      "before" => "旧タイトル",
      "after" => "新タイトル",
      "auto_revision" => true
    }
  end

  def create_ready_codex_task
    create_profile!
    candidate = create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")
    AutoRevisionTask.from_action_candidate(candidate).tap do |task|
      task.update!(status: "ready_for_codex", risk_level: "low", approved_at: Time.current)
    end
  end

  def create_profile!
    businesses(:suelog).create_business_execution_profile!(
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
end
