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
      assert_includes draft.prompt_body, "【共通ルール】"
      assert_includes draft.prompt_body, "【サービス固有ルール】"
      assert_includes draft.prompt_body, "【今回の依頼】"
      assert_includes draft.prompt_body, "AicooActivityLogger.log"
      assert_includes draft.prompt_body, "吸えログ Activity Loggingルール"
      assert_includes draft.prompt_body, "ActionCandidate実行指示書"
      assert_includes draft.prompt_body, "現在 → 変更後"
      assert_includes draft.prompt_body, "変更ファイル"
      assert_includes draft.prompt_body, "完了条件"
      assert draft.metadata.dig("execution_brief", "before_after_items").present?
    end

    test "includes business codex execution target settings" do
      business = businesses(:suelog)
      BusinessExecutionProfile.create!(
        business:,
        execution_type: "external_repo",
        repository_name: "service-app",
        github_repository: "owner/service-app",
        repository_path: "/apps/service-app",
        target_slug: "service-lp",
        target_paths_text: "app/views/public\napp/services/service",
        test_command: "bin/test",
        deploy_command: "bin/deploy",
        default_branch: "develop",
        auto_deploy_enabled: true
      )
      candidate = action_candidates(:nagazakicho_article)

      draft = CodexPromptDraftBuilder.new(candidate).call

      assert_includes draft.prompt_body, "Codex実行先設定"
      assert_includes draft.prompt_body, "execution_type: external_repo"
      assert_includes draft.prompt_body, "github_repo: owner/service-app"
      assert_includes draft.prompt_body, "local_project_path: /apps/service-app"
      assert_includes draft.prompt_body, "target_slug: service-lp"
      assert_includes draft.prompt_body, "- app/views/public"
      assert_includes draft.prompt_body, "test_command: bin/test"
      assert_includes draft.prompt_body, "deploy_command: bin/deploy"
      assert_includes draft.prompt_body, "default_branch: develop"
      assert_includes draft.prompt_body, "auto_deploy_enabled: true"
      assert_equal "external_repo", draft.metadata.dig("codex_execution_target", "execution_type")
    end

    test "uses aicoo internal execution target for aicoo created business" do
      business = businesses(:suelog)
      business.update!(created_by_aicoo: true, project_key: nil, local_project_path: nil, repository_name: nil)
      candidate = action_candidates(:nagazakicho_article)

      draft = CodexPromptDraftBuilder.new(candidate).call

      assert_equal "aicoo_internal", draft.project_key
      assert_equal Rails.root.to_s, draft.local_project_path
      assert_includes draft.prompt_body, "execution_type: aicoo_internal"
      assert_includes draft.prompt_body, "github_repo: soregaaashiii/aicoo"
      assert_includes draft.prompt_body, "aicoo_internal: AICOO本体のLP、Business、設定、管理画面を対象にする"
      assert_equal "aicoo_internal", draft.metadata.dig("codex_execution_target", "execution_type")
    end

    test "external execution profile overrides aicoo created business internal target" do
      business = businesses(:suelog)
      business.update!(created_by_aicoo: true, project_key: nil, local_project_path: nil, repository_name: nil)
      BusinessExecutionProfile.create!(
        business:,
        execution_type: "external_repo",
        repository_name: "suelog",
        github_repository: "soregaaashiii/suelog",
        repository_path: "/Users/example/suelog",
        test_command: "bin/rails test",
        default_branch: "main"
      )
      candidate = action_candidates(:nagazakicho_article)

      draft = CodexPromptDraftBuilder.new(candidate).call

      assert_equal "suelog", draft.project_key
      assert_equal "/Users/example/suelog", draft.local_project_path
      assert_includes draft.prompt_body, "execution_type: external_repo"
      assert_includes draft.prompt_body, "github_repo: soregaaashiii/suelog"
      assert_includes draft.prompt_body, "local_project_path: /Users/example/suelog"
      assert_includes draft.prompt_body, "external_repo: 別サービスのリポジトリを対象にする"
      assert_equal "external_repo", draft.metadata.dig("codex_execution_target", "execution_type")
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

    test "includes action expansion execution guide" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "とり友 梅田 の順位改善",
        action_type: "seo_improvement",
        status: "approved",
        immediate_value_yen: 10_000,
        success_probability: 0.8,
        execution_prompt: "順位改善してください。",
        metadata: {
          "evidence" => {
            "score" => "82",
            "warning" => false,
            "items" => [
              {
                "source" => "gsc",
                "metric_name" => "impressions",
                "current_value" => "1200",
                "confidence" => "82",
                "page" => "/umeda/toritomo",
                "keyword" => "とり友 梅田 喫煙"
              }
            ]
          }
        }
      )
      candidate.update_columns(
        metadata: candidate.metadata.merge(
          "action_expansion" => {
            "expanded" => true,
            "target" => "/umeda/toritomo",
            "target_url" => "/umeda/toritomo",
            "target_keyword" => "とり友 梅田 喫煙",
            "expected_minutes" => 35,
            "execution_steps" => [ "対象ページを開く", "SEOタイトルを改訂する" ],
            "completion_criteria" => [ "対象KWが記録されている", "タイトルが改訂されている" ],
            "warning" => false
          }
        )
      )

      draft = CodexPromptDraftBuilder.new(candidate).call

      assert_includes draft.prompt_body, "Execution Guide"
      assert_includes draft.prompt_body, "ActionCandidate実行指示書"
      assert_includes draft.prompt_body, "実行手順"
      assert_includes draft.prompt_body, "完了条件"
      assert_includes draft.prompt_body, "現在: 吸えログ｜とり友 梅田 喫煙"
      assert_includes draft.prompt_body, "変更後: 【#{Date.current.year}年版】とり友 梅田 喫煙｜吸えログ"
      assert_includes draft.prompt_body, "変更ファイル"
      assert_equal true, draft.metadata.dig("action_expansion", "expanded")
      assert_equal "とり友 梅田 喫煙", draft.metadata.dig("execution_brief", "openai_context", "serp", "query")
    end
  end
end
