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
      assert_includes prompt, "① 検索クエリ"
      assert_includes prompt, "② SERP上位5件"
      assert_includes prompt, "③ 上位サイト共通要素"
      assert_includes prompt, "④ 自サイトとの差分"
      assert_includes prompt, "⑤ 改善対象ページ"
      assert_includes prompt, "⑥ 新規記事か既存記事か"
      assert_includes prompt, "期待CTR"
      assert_includes prompt, "期待順位"
      assert_includes prompt, "期待利益"
      assert_includes prompt, "AICOOは判断情報だけを渡します"
      assert_no_match(/Codexへ渡す修正文|After（AI生成）|現在 → 変更後/, prompt)
      assert_includes prompt, "候補ページ"
      assert_includes prompt, "db:drop / db:reset / drop database"
    end
  end
end
