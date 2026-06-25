require "test_helper"

module Aicoo
  class CodexPromptDraftBuilderTest < ActiveSupport::TestCase
    test "copies business project settings into draft" do
      business = businesses(:suelog)
      business.update!(
        project_key: "suelog",
        local_project_path: "/Users/example/suelog",
        repository_name: "suelog-app",
        default_verification_commands: [ "bin/rails test:models", "bundle exec rubocop" ]
      )
      candidate = action_candidates(:nagazakicho_article)

      draft = CodexPromptDraftBuilder.new(candidate).call

      assert_equal "suelog", draft.project_key
      assert_equal "/Users/example/suelog", draft.local_project_path
      assert_equal [ "bin/rails test:models", "bundle exec rubocop" ], draft.verification_commands
      assert_includes draft.prompt_body, "project_key: suelog"
      assert_includes draft.prompt_body, "local_project_path: /Users/example/suelog"
      assert_includes draft.prompt_body, "repository_name: suelog-app"
    end

    test "creates draft without project settings" do
      business = businesses(:suelog)
      business.update!(project_key: nil, local_project_path: nil, repository_name: nil)
      candidate = action_candidates(:nagazakicho_article)

      draft = CodexPromptDraftBuilder.new(candidate).call

      assert_nil draft.project_key
      assert_nil draft.local_project_path
      assert_includes draft.prompt_body, "project_key: 未設定"
      assert_equal CodexPromptDraft::DEFAULT_VERIFICATION_COMMANDS, draft.verification_commands
    end

    test "estimates risk level" do
      low = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "SEOタイトル文言を改善",
        action_type: "seo_improvement",
        status: "approved",
        immediate_value_yen: 1_000,
        success_probability: 1
      )
      high = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "認証とmigrationを変更",
        action_type: "feature_development",
        status: "approved",
        immediate_value_yen: 1_000,
        success_probability: 1,
        execution_prompt: "db:migrateを含む認証変更"
      )

      assert_equal "low", CodexPromptDraftBuilder.new(low).call.risk_level
      assert_equal "high", CodexPromptDraftBuilder.new(high).call.risk_level
    end
  end
end
