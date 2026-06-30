require "test_helper"

class CodexPromptRuleTest < ActiveSupport::TestCase
  test "creates default global and suelog rules" do
    CodexPromptRule.delete_all

    assert_difference("CodexPromptRule.count", 4) do
      CodexPromptRule.ensure_defaults!
    end

    assert CodexPromptRule.global_rules.exists?(name: "AICOO共通開発ルール")
    assert CodexPromptRule.global_rules.exists?(name: "AICOO Activity Logging共通ルール")
    assert CodexPromptRule.global_rules.exists?(name: "AICOOテストルール")
    assert CodexPromptRule.service_rules.exists?(name: "吸えログ Activity Loggingルール", business: businesses(:suelog))
  end

  test "service rules require business and global rules reject business" do
    service_rule = CodexPromptRule.new(
      name: "service without business",
      scope: "service",
      rule_category: "service_specific",
      content: "rule"
    )
    assert_not service_rule.valid?

    global_rule = CodexPromptRule.new(
      name: "global with business",
      scope: "global",
      business: businesses(:suelog),
      rule_category: "core",
      content: "rule"
    )
    assert_not global_rule.valid?
  end
end
