require "test_helper"

module Admin
  class CodexPromptRulesControllerTest < ActionDispatch::IntegrationTest
    test "shows rule index and seeds defaults" do
      CodexPromptRule.delete_all

      get admin_codex_prompt_rules_url

      assert_response :success
      assert_includes response.body, "Codex Prompt Rules"
      assert_includes response.body, "AICOO共通開発ルール"
      assert_includes response.body, "吸えログ Activity Loggingルール"
    end

    test "updates rule content and priority" do
      CodexPromptRule.ensure_defaults!
      rule = CodexPromptRule.global_rules.find_by!(name: "AICOO共通開発ルール")

      patch admin_codex_prompt_rule_url(rule), params: {
        codex_prompt_rule: {
          name: rule.name,
          rule_category: rule.rule_category,
          priority: 99,
          active: "1",
          content: "更新した共通ルール"
        }
      }

      assert_redirected_to admin_codex_prompt_rules_url
      assert_equal 99, rule.reload.priority
      assert_equal "更新した共通ルール", rule.content
    end

    test "toggles active state" do
      CodexPromptRule.ensure_defaults!
      rule = CodexPromptRule.global_rules.first

      assert_changes -> { rule.reload.active? } do
        patch toggle_admin_codex_prompt_rule_url(rule)
      end
    end

    test "previews final prompt" do
      CodexPromptRule.ensure_defaults!

      post admin_codex_prompt_rules_preview_url, params: {
        business_id: businesses(:suelog).id,
        request_body: "店舗公開処理を改善してください。"
      }

      assert_response :success
      assert_includes response.body, "最終プロンプト"
      assert_includes response.body, "【共通ルール】"
      assert_includes response.body, "【サービス固有ルール】"
      assert_includes response.body, "店舗公開処理を改善してください。"
    end
  end
end
