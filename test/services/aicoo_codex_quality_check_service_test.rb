require "test_helper"

class AicooCodexQualityCheckServiceTest < ActiveSupport::TestCase
  test "passes when tests are green and no warnings" do
    task = create_task(
      changed_files: "app/views/articles/show.html.erb",
      test_result: "621 runs, 4387 assertions, 0 failures, 0 errors\nAll is good!\n443 files inspected, no offenses detected"
    )

    check = AicooCodexQualityCheckService.new(task).call

    assert_equal "passed", check.result
    assert_equal "passed", check.test_status
    assert_equal "approved", check.approval_status
    assert_not_nil check.approved_at
    assert_operator check.quality_score, :>=, 80
    assert_equal 0, check.warning_count
  end

  test "detects migration" do
    task = create_task(
      changed_files: "db/migrate/20260623000000_add_column.rb",
      test_result: "0 failures"
    )

    check = AicooCodexQualityCheckService.new(task).call

    assert_equal true, check.migration_detected
    assert_includes check.warnings, "migration変更を検知しました"
  end

  test "detects high risk changed files" do
    task = create_task(
      changed_files: "app/services/daily_runner.rb\nconfig/credentials.yml.enc",
      test_result: "0 failures"
    )

    check = AicooCodexQualityCheckService.new(task).call

    assert_equal true, check.high_risk_change_detected
    assert_includes check.warnings, "高リスク領域の変更を検知しました"
  end

  test "returns passed with warnings" do
    task = create_task(
      changed_files: "db/migrate/20260623000000_add_column.rb",
      test_result: "0 failures"
    )

    check = AicooCodexQualityCheckService.new(task).call

    assert_equal "passed_with_warnings", check.result
    assert_equal "pending", check.approval_status
  end

  test "returns review required for multiple warnings" do
    task = create_task(
      changed_files: "db/migrate/20260623000000_add_column.rb\nconfig/credentials.yml.enc",
      test_result: "",
      risk_level: "high"
    )

    check = AicooCodexQualityCheckService.new(task).call

    assert_equal "review_required", check.result
    assert_equal "pending", check.approval_status
    assert_operator check.warning_count, :>=, 3
  end

  test "returns failed for failing tests" do
    task = create_task(
      changed_files: "app/models/example.rb",
      test_result: "Failure: test failed with exception"
    )

    check = AicooCodexQualityCheckService.new(task).call

    assert_equal "failed", check.result
    assert_equal "failed", check.test_status
    assert_equal "rejected", check.approval_status
  end

  private

  def create_task(changed_files:, test_result:, risk_level: "low")
    AutoRevisionTask.create!(
      action_candidate: action_candidates(:nagazakicho_article),
      business: businesses(:suelog),
      title: "Quality check task #{SecureRandom.hex(4)}",
      execution_prompt: "SEOタイトルを改善してください。",
      status: "succeeded",
      risk_level:,
      changed_files:,
      test_result:
    )
  end
end
