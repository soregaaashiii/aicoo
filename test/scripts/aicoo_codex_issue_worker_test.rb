require "minitest/autorun"
require "stringio"
require_relative "../../script/aicoo_codex_issue_worker"

class AicooCodexIssueWorkerTest < Minitest::Test
  def setup
    @worker = AicooCodexIssueWorker.new(
      env: {
        "GITHUB_TOKEN" => "token",
        "GITHUB_REPOSITORY" => "example/aicoo",
        "ISSUE_NUMBER" => "1",
        "OPENAI_API_KEY" => "openai"
      },
      stdout: StringIO.new
    )
  end

  def test_target_issue_accepts_aicoo_codex_label
    issue = { "labels" => [ { "name" => "aicoo-codex" } ] }

    assert @worker.send(:target_issue?, issue)
  end

  def test_target_issue_accepts_legacy_aicoo_and_codex_labels
    issue = { "labels" => [ { "name" => "aicoo" }, { "name" => "codex" } ] }

    assert @worker.send(:target_issue?, issue)
  end

  def test_risk_limit_defaults_to_low
    issue = { "labels" => [ { "name" => "risk:medium" } ] }

    refute @worker.send(:risk_allowed?, issue)
  end

  def test_allowed_check_command_rejects_destructive_commands
    refute @worker.send(:allowed_check_command?, "bin/rails db:drop")
    refute @worker.send(:allowed_check_command?, "git reset --hard")
  end

  def test_allowed_check_command_accepts_safe_default_commands
    assert @worker.send(:allowed_check_command?, "bin/rails test")
  end

  def test_extracts_codex_submission_id_from_issue_body
    issue = { "body" => "- CodexSubmission ID: 123\n- AutoRevisionTask ID: 456" }

    assert_equal "123", @worker.send(:codex_submission_id, issue)
  end

  def test_builds_callback_url_from_base_url
    worker = AicooCodexIssueWorker.new(
      env: {
        "AICOO_CODEX_CALLBACK_URL" => "https://aicoo.onrender.com",
        "GITHUB_TOKEN" => "token",
        "GITHUB_REPOSITORY" => "example/aicoo",
        "ISSUE_NUMBER" => "1",
        "OPENAI_API_KEY" => "openai"
      },
      stdout: StringIO.new
    )

    assert_equal(
      "https://aicoo.onrender.com/api/aicoo/codex_submissions/123/github_tracking",
      worker.send(:callback_url, "123")
    )
  end
end
