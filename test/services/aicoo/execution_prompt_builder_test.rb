require "test_helper"

module Aicoo
  class ExecutionPromptBuilderTest < ActiveSupport::TestCase
    test "builds execution prompt from action candidate" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "CTR改善",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.7,
        expected_hours: 2,
        execution_prompt: "タイトルを改善してください。",
        evaluation_reason: "検索流入のCTRが低いため"
      )

      prompt = ExecutionPromptBuilder.new(candidate).call

      assert_includes prompt, "CTR改善"
      assert_includes prompt, "期待利益"
      assert_includes prompt, "成功確率"
      assert_includes prompt, "検索流入のCTRが低いため"
      assert_includes prompt, "タイトルを改善してください。"
      assert_includes prompt, "db:drop / db:reset / drop database"
    end
  end
end
