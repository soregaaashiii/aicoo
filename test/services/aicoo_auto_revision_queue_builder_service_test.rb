require "test_helper"

class AicooAutoRevisionQueueBuilderServiceTest < ActiveSupport::TestCase
  setup do
    AutoRevisionRunLog.delete_all
    CodexSubmission.delete_all
    AutoRevisionTask.delete_all
    ActionCandidate.update_all(status: "done")
    Business.update_all(auto_revision_mode: "manual")
    businesses(:suelog).business_execution_profile&.destroy!
  end

  test "manual mode creates draft proposal only" do
    candidate = create_candidate(title: "SEOタイトルを改善する", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionQueueBuilderService.new.call

    assert_equal 1, result.created_count
    task = AutoRevisionTask.last
    assert_equal candidate, task.action_candidate
    assert_equal "draft", task.status
    assert_equal "low", task.risk_level
    assert_equal candidate.reload.final_score.to_d, task.priority_score
    assert_equal "manual_proposal", result.logs.last.metadata["action"]
  end

  test "approval mode auto releases task when owner judgment reason is absent" do
    businesses(:suelog).update!(auto_revision_mode: "approval")
    candidate = create_candidate(title: "SEOタイトルを改善する", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionQueueBuilderService.new.call

    assert_equal 1, result.created_count
    assert_equal "ready_for_codex", AutoRevisionTask.last.status
    assert_equal "pending", result.logs.last.status
    assert_equal "auto_released_no_owner_approval_reason", result.logs.last.metadata["action"]
    assert_not AutoRevisionTask.last.owner_approval_required?
  end

  test "excludes candidate without execution prompt" do
    create_candidate(title: "promptなし", execution_prompt: nil)

    assert_no_difference("AutoRevisionTask.count") do
      AicooAutoRevisionQueueBuilderService.new.call
    end
  end

  test "excludes inactive candidates" do
    %w[archived rejected done].each do |status|
      create_candidate(title: "#{status} candidate", status:, execution_prompt: "文言を改善してください。")
    end

    assert_no_difference("AutoRevisionTask.count") do
      AicooAutoRevisionQueueBuilderService.new.call
    end
  end

  test "skips non code revision candidates" do
    candidate = create_candidate(title: "大阪エリアの掲載店舗を80件追加する", execution_prompt: "大阪エリアの店舗を追加してください。")
    candidate.update_columns(
      metadata: candidate.metadata.to_h.merge(
        "execution_mode" => "data_operation",
        "seo_action_type" => "add_listings"
      )
    )

    assert_no_difference("AutoRevisionTask.count") do
      result = AicooAutoRevisionQueueBuilderService.new.call

      assert_equal 0, result.created_count
      assert_equal 1, result.skipped_count
      assert_equal "non_code_revision:data_operation", result.skipped_reasons.first["reason"]
    end
  end

  test "skips candidates blocked by ranking guard" do
    candidate = create_candidate(
      title: "「吸えログ 比較」 / https://it-trend.jp/log_management/article/84-0008 向けの記事を1本作成する",
      execution_prompt: "https://it-trend.jp/log_management/article/84-0008 を参考に記事を作ってください。"
    )
    candidate.update_columns(
      metadata: candidate.metadata.to_h.merge(
        "reference_urls" => [ "https://it-trend.jp/log_management/article/84-0008" ],
        "article_plan" => { "title" => "ログ管理の比較記事" },
        "execution_mode" => "code_revision"
      )
    )

    assert_no_difference("AutoRevisionTask.count") do
      result = AicooAutoRevisionQueueBuilderService.new.call

      assert_equal 0, result.created_count
      assert_equal 1, result.skipped_count
      assert_equal "ranking_guard:irrelevant_external_evidence", result.skipped_reasons.first["reason"]
    end
  end

  test "skips unresolved target code revision candidates" do
    candidate = create_candidate(
      title: "電話・地図・アフィリエイト導線を5ページに追加する",
      execution_prompt: "対象ページを見つけて導線を改善してください。"
    )
    candidate.update_columns(
      metadata: candidate.metadata.to_h.merge(
        "execution_mode" => "code_revision",
        "target_url_warning" => "対象ページ未特定",
        "owner_next_step" => "対象ページを特定する"
      )
    )

    assert_no_difference("AutoRevisionTask.count") do
      result = AicooAutoRevisionQueueBuilderService.new.call

      assert_equal 0, result.created_count
      assert_equal 1, result.skipped_count
      assert_equal "target_unresolved_for_codex", result.skipped_reasons.first["reason"]
    end
  end

  test "high risk candidates are reported and kept for manual proposal" do
    candidate = create_candidate(
      title: "DB migrationで認証credentialを変更する",
      execution_prompt: "DB migrationを追加し、tokenを扱う設定を変更してください。"
    )

    result = AicooAutoRevisionQueueBuilderService.new.call

    assert_equal 1, result.created_count
    assert_equal [ candidate ], result.high_risk_candidates
    assert_equal "draft", AutoRevisionTask.last.status
  end

  test "does not duplicate existing unfinished auto revision task" do
    candidate = create_candidate(title: "表示文言改善", execution_prompt: "表示文言を改善してください。")
    AutoRevisionTask.from_action_candidate(candidate)

    assert_no_difference("AutoRevisionTask.count") do
      AicooAutoRevisionQueueBuilderService.new.call
    end
  end

  test "creates at most five tasks" do
    7.times do |index|
      create_candidate(title: "SEOタイトル改善 #{index}", execution_prompt: "SEOタイトルを改善してください。")
    end

    result = AicooAutoRevisionQueueBuilderService.new.call

    assert_equal 5, result.created_count
    assert_equal 5, AutoRevisionTask.count
  end

  test "respects custom minimum final score" do
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionQueueBuilderService.new(minimum_final_score: 99_999).call

    assert_equal 0, result.created_count
    assert_equal 0, AutoRevisionTask.count
  end

  test "automatic mode fails with reason when execution profile is missing" do
    businesses(:suelog).update!(auto_revision_mode: "automatic")
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    assert_equal "failed", AutoRevisionTask.last.status
    assert_equal "precheck_failed", AutoRevisionRunLog.last.status
    assert_includes AutoRevisionRunLog.last.message, "Execution Profile"
  end

  test "automatic mode creates github issue for low risk candidate without owner action" do
    businesses(:suelog).update!(auto_revision_mode: "automatic")
    create_profile_without_candidate!

    with_fake_github_issue_bridge do
      create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")
      task = AutoRevisionTask.last
      assert_equal "sent_to_codex", task.status
      assert_equal "sent_to_codex", AutoRevisionRunLog.last.status
      assert_equal "sent_to_codex", AutoRevisionRunLog.last.metadata["action"]
      assert_equal "https://github.com/example/suelog/issues/#{task.id}", task.codex_submission.github_issue_url
      assert_includes AutoRevisionRunLog.last.message, "GitHub Issue作成まで自動実行"
    end
  end

  test "automatic mode keeps owner-only decision waiting with reason" do
    businesses(:suelog).update!(auto_revision_mode: "automatic")
    create_candidate(title: "広告費の予算を増やす", execution_prompt: "広告費の予算を増やしてください。")

    assert_equal "waiting_approval", AutoRevisionTask.last.status
    assert_equal "queued_for_approval", AutoRevisionRunLog.last.status
    assert_equal "approval_required_due_to_risk", AutoRevisionRunLog.last.metadata["action"]
    assert_includes AutoRevisionTask.last.approval_required_reason, "お金"
  end

  private

  def create_candidate(title:, execution_prompt:, status: "idea")
    ActionCandidate.create!(
      business: businesses(:suelog),
      title:,
      action_type: "seo_improvement",
      status:,
      immediate_value_yen: 20_000,
      success_probability: 1,
      expected_hours: 1,
      execution_prompt:
    )
  end

  def create_profile_without_candidate!
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
