require "test_helper"

module Aicoo
  class ActionCandidateUpserterTest < ActiveSupport::TestCase
    test "blocks irrelevant external evidence before creating action candidate" do
      business = businesses(:suelog)

      assert_no_difference("ActionCandidate.count") do
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

        assert_nil candidate
      end
    end

    test "does not create candidate for deleted business" do
      business = businesses(:suelog)
      business.update_columns(deleted_at: Time.current, deletion_reason: "SERP誤生成")

      assert_no_difference("ActionCandidate.count") do
        candidate = Aicoo::ActionCandidateUpserter.call(
          business:,
          attributes: {
            title: "削除済みBusinessの改善候補",
            description: "削除済みなので作らない",
            action_type: "seo_improvement",
            generation_source: "ai_business",
            immediate_value_yen: 10_000,
            success_probability: 0.5,
            expected_hours: 1,
            metadata: {}
          }
        )

        assert_nil candidate
      end
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

    test "keeps different action types for same opportunity as separate actions" do
      business = businesses(:suelog)
      base_attributes = {
        title: "吸えログ比較記事を1本作成する",
        description: "検索需要に対応する",
        generation_source: "business_analyzer",
        immediate_value_yen: 10_000,
        success_probability: 0.4,
        expected_hours: 2,
        metadata: {
          "opportunity_key" => "gsc:query:suelog-comparison",
          "source_query" => "吸えログ 比較",
          "concrete_task" => "吸えログ比較記事を1本作成する",
          "execution_mode" => "content_creation"
        }
      }

      first = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: base_attributes.merge(action_type: "new_article_candidate")
      )
      second = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: base_attributes.merge(
          title: "吸えログ比較ページのtitle/metaを改善する",
          action_type: "seo_improvement",
          metadata: base_attributes[:metadata].merge("concrete_task" => "吸えログ比較ページのtitle/metaを改善する")
        )
      )

      assert_not_equal first.id, second.id
    end

    test "dedupe key includes execution mode department and generation source" do
      business = businesses(:suelog)
      base_attributes = {
        title: "吸えログ比較記事を1本作成する",
        description: "検索需要に対応する記事を作る",
        action_type: "new_article_candidate",
        immediate_value_yen: 10_000,
        success_probability: 0.4,
        expected_hours: 2,
        metadata: {
          "opportunity_key" => "gsc:query:suelog-comparison",
          "source_query" => "吸えログ 比較",
          "concrete_task" => "吸えログ比較記事を1本作成する",
          "execution_mode" => "content_creation"
        }
      }

      first = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: base_attributes.merge(generation_source: "business_analyzer", department: "revenue")
      )
      second = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: base_attributes.deep_merge(
          generation_source: "suelog_db",
          department: "revenue",
          metadata: { "execution_mode" => "content_creation" }
        )
      )
      third = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: base_attributes.deep_merge(
          generation_source: "business_analyzer",
          department: "revenue",
          metadata: { "execution_mode" => "manual_operation" }
        )
      )

      assert_not_equal first.id, second.id
      assert_not_equal first.id, third.id
    end
  end
end
