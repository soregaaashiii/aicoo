require "test_helper"

class CodexQualityChecksControllerTest < ActionDispatch::IntegrationTest
  test "shows quality gate index" do
    quality_check = create_quality_check(result: "review_required", approval_status: "pending")

    get codex_quality_checks_url

    assert_response :success
    assert_includes response.body, "Quality Gate"
    assert_includes response.body, quality_check.auto_revision_task.title
    assert_includes response.body, "pending"
    assert_includes response.body, "review_required"
  end

  test "filters quality gate index" do
    pending = create_quality_check(result: "review_required", approval_status: "pending")
    approved = create_quality_check(result: "passed", approval_status: "approved")

    get codex_quality_checks_url(filter: "pending")

    assert_response :success
    assert_includes response.body, pending.auto_revision_task.title
    assert_not_includes response.body, approved.auto_revision_task.title
  end

  test "shows quality gate detail" do
    quality_check = create_quality_check(result: "passed_with_warnings", approval_status: "pending")

    get codex_quality_check_url(quality_check)

    assert_response :success
    assert_includes response.body, "Quality Gate ##{quality_check.id}"
    assert_includes response.body, "品質スコア"
    assert_includes response.body, "承認"
    assert_includes response.body, "却下"
  end

  test "approves quality gate" do
    quality_check = create_quality_check(result: "review_required", approval_status: "pending")

    patch approve_codex_quality_check_url(quality_check)

    assert_redirected_to codex_quality_check_url(quality_check)
    quality_check.reload
    assert_equal "approved", quality_check.approval_status
    assert_equal "owner", quality_check.approved_by
    assert_not_nil quality_check.approved_at
  end

  test "rejects quality gate" do
    quality_check = create_quality_check(result: "review_required", approval_status: "pending")

    patch reject_codex_quality_check_url(quality_check)

    assert_redirected_to codex_quality_check_url(quality_check)
    quality_check.reload
    assert_equal "rejected", quality_check.approval_status
    assert_equal "owner", quality_check.approved_by
    assert_nil quality_check.approved_at
  end

  private

  def create_quality_check(result:, approval_status:)
    task = AutoRevisionTask.create!(
      action_candidate: action_candidates(:nagazakicho_article),
      business: businesses(:suelog),
      title: "Quality Gate task #{SecureRandom.hex(4)}",
      execution_prompt: "SEOタイトルを改善してください。",
      status: "succeeded",
      risk_level: "low"
    )
    task.create_codex_quality_check!(
      result:,
      approval_status:,
      quality_score: 70,
      risk_score: 30,
      test_status: "passed",
      warning_count: 1,
      warnings: [ "確認が必要です" ]
    )
  end
end
