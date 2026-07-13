require "test_helper"

module Aicoo
  class ActionCandidateUpserterTest < ActiveSupport::TestCase
    test "moves external target url to references before creating candidate" do
      business = businesses(:suelog)

      candidate = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: {
          title: "吸えログ比較ページを改善する",
          description: "競合の比較表を参考に吸えログを改善する",
          action_type: "seo_improvement",
          generation_source: "business_analyzer",
          immediate_value_yen: 10_000,
          success_probability: 0.5,
          expected_hours: 1,
          metadata: {
            "target_url" => "https://it-trend.jp/log_management/article/84-0008",
            "source_query" => "吸えログ 比較",
            "action_plan" => { "owner_output" => "吸えログ比較ページを改善する" }
          }
        }
      )

      metadata = candidate.reload.metadata
      assert_equal "https://suelog.jp/", metadata["target_url"]
      assert_equal "owner_page", metadata["target_url_type"]
      assert_includes metadata["reference_urls"], "https://it-trend.jp/log_management/article/84-0008"
      assert_includes metadata["competitor_urls"], "https://it-trend.jp/log_management/article/84-0008"
    end

    test "updates existing action instead of creating duplicate for same opportunity" do
      business = businesses(:suelog)
      attributes = {
        title: "吸えログ比較記事を1本作成する",
        description: "検索需要に対応する記事を作る",
        action_type: "new_article_candidate",
        generation_source: "business_analyzer",
        immediate_value_yen: 10_000,
        success_probability: 0.4,
        expected_hours: 2,
        evaluation_reason: "first",
        metadata: {
          "opportunity_key" => "gsc:query:suelog-comparison",
          "source_query" => "吸えログ 比較",
          "recommended_slug" => "suelog-comparison",
          "concrete_task" => "吸えログ比較記事を1本作成する"
        }
      }

      first = Aicoo::ActionCandidateUpserter.call(business:, attributes:)

      assert_no_difference("ActionCandidate.count") do
        second = Aicoo::ActionCandidateUpserter.call(
          business:,
          attributes: attributes.deep_merge(
            immediate_value_yen: 30_000,
            success_probability: 0.6,
            evaluation_reason: "second",
            metadata: { "serp_top_results" => [ { "url" => "https://example.com/ref" } ] }
          )
        )
        assert_equal first.id, second.id
      end

      first.reload
      assert_equal 30_000, first.immediate_value_yen
      assert_equal 0.6, first.success_probability
      assert_equal "second", first.evaluation_reason
      assert_equal 1, first.metadata["dedupe_merged_count"]
    end
  end
end
