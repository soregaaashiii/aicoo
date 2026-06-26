require "test_helper"

module Aicoo
  class ActionExpansionEngineTest < ActiveSupport::TestCase
    test "expands abstract ranking improvement from gsc evidence" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "とり友 梅田 の順位改善",
        action_type: "seo_improvement",
        execution_prompt: "順位改善してください。",
        metadata: {
          "evidence" => {
            "score" => "82",
            "warning" => false,
            "items" => [
              {
                "source" => "gsc",
                "title" => "検索流入指標",
                "summary" => "表示回数が増えています。",
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

      result = ActionExpansionEngine.new(candidate).call

      assert result.expanded
      assert_equal "/umeda/toritomo", result.metadata["target_url"]
      assert_equal "とり友 梅田 喫煙", result.metadata["target_keyword"]
      assert_includes result.metadata["execution_steps"].join(" "), "SEOタイトル"
      assert_includes result.metadata["completion_criteria"].join(" "), "対象KW"
    end

    test "warns when evidence is missing" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "記事改善",
        action_type: "seo_improvement",
        metadata: { "evidence" => { "score" => "10", "warning" => true } }
      )

      result = ActionExpansionEngine.new(candidate).call

      assert_not result.expanded
      assert result.metadata["warning"]
      assert_match(/Evidence不足/, result.metadata["warning_reason"])
    end
  end
end
