require "test_helper"

module Aicoo
  class CodexPromptComposerTest < ActiveSupport::TestCase
    test "prepends global and service rules before request body" do
      CodexPromptRule.ensure_defaults!

      prompt = CodexPromptComposer.call(
        business: businesses(:suelog),
        request_body: "【依頼】記事更新を実装してください。"
      )

      assert_includes prompt, "【共通ルール】"
      assert_includes prompt, "【AICOO共通開発ルール】"
      assert_includes prompt, "【AICOO Activity Logging共通ルール】"
      assert_includes prompt, "【サービス固有ルール】"
      assert_includes prompt, "【吸えログ Activity Loggingルール】"
      assert_includes prompt, "shop_created"
      assert_includes prompt, "【今回の依頼】"
      assert_includes prompt, "記事更新を実装してください"
      assert_operator prompt.index("【共通ルール】"), :<, prompt.index("【今回の依頼】")
    end

    test "works without business" do
      prompt = CodexPromptComposer.call(business: nil, request_body: "共通だけで作る")

      assert_includes prompt, "Business未選択"
      assert_includes prompt, "共通だけで作る"
    end
  end
end
