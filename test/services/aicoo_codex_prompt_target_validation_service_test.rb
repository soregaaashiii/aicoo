require "test_helper"

class AicooCodexPromptTargetValidationServiceTest < ActiveSupport::TestCase
  test "configured profile is valid" do
    create_configured_profile
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    result = AicooCodexPromptTargetValidationService.new(task).call

    assert result.valid?
    assert_equal "valid", result.target_status
    assert_empty result.errors
  end

  test "missing profile is invalid" do
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    result = AicooCodexPromptTargetValidationService.new(task).call

    assert result.invalid?
    assert_includes result.missing_items, "business_execution_profile"
    assert result.errors.any? { |message| message.include?("BusinessExecutionProfile") }
  end

  test "inactive profile is invalid" do
    create_configured_profile(active: false)
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))

    result = AicooCodexPromptTargetValidationService.new(task).call

    assert result.invalid?
    assert_includes result.missing_items, "active"
  end

  test "target repository name mismatch is invalid" do
    create_configured_profile(repository_name: "suelog")
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.update!(target_repository_name: "wrong-repo")

    result = AicooCodexPromptTargetValidationService.new(task).call

    assert result.invalid?
    assert_includes result.missing_items, "target_repository_name"
  end

  test "missing forbidden patterns from prompt is invalid" do
    create_configured_profile(forbidden_patterns: "db:drop\ndestroy_all")
    task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    task.define_singleton_method(:codex_prompt) { "目的だけのプロンプト" }

    result = AicooCodexPromptTargetValidationService.new(task).call

    assert result.invalid?
    assert_includes result.missing_items, "forbidden_patterns"
  end

  private

  def create_configured_profile(attributes = {})
    BusinessExecutionProfile.create!(
      {
        business: businesses(:suelog),
        repository_name: "suelog",
        repository_type: "rails",
        repository_path: "/apps/suelog",
        github_repository: "kawamura/suelog",
        test_command: "bin/rails test",
        lint_command: "bundle exec rubocop",
        deploy_command: "bin/deploy"
      }.merge(attributes)
    )
  end
end
