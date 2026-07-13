require "test_helper"

module Aicoo
  class OpportunityLinkerTest < ActiveSupport::TestCase
    test "upserter links same detection to one opportunity and updates it" do
      business = businesses(:suelog)
      attributes = candidate_attributes(
        title: "「吸えログ 比較」向けの記事を作成する",
        action_type: "new_article_candidate"
      )

      assert_difference("OpportunityDiscoveryItem.count", 1) do
        @first = Aicoo::ActionCandidateUpserter.call(business:, attributes:)
      end
      assert_no_difference("OpportunityDiscoveryItem.count") do
        @second = Aicoo::ActionCandidateUpserter.call(business:, attributes: attributes.merge(immediate_value_yen: 120_000))
      end

      assert_equal @first.id, @second.id
      opportunity = OpportunityDiscoveryItem.find(@second.metadata["opportunity_id"])
      assert_equal 120_000, opportunity.expected_value_yen
      assert_equal @second.metadata["opportunity_identity_key"], opportunity.metadata["opportunity_identity_key"]
    end

    test "same opportunity can have different action candidates but not duplicate work" do
      business = businesses(:suelog)

      assert_difference("OpportunityDiscoveryItem.count", 1) do
        @article = Aicoo::ActionCandidateUpserter.call(
          business:,
          attributes: candidate_attributes(title: "比較記事を1本作成する", action_type: "new_article_candidate")
        )
      end
      assert_no_difference("OpportunityDiscoveryItem.count") do
        @link = Aicoo::ActionCandidateUpserter.call(
          business:,
          attributes: candidate_attributes(title: "関連ページから内部リンクを追加する", action_type: "seo_improvement")
        )
      end
      assert_no_difference("ActionCandidate.count") do
        Aicoo::ActionCandidateUpserter.call(
          business:,
          attributes: candidate_attributes(title: "関連ページから内部リンクを追加する", action_type: "seo_improvement")
        )
      end

      assert_not_equal @article.id, @link.id
      assert_equal @article.metadata["opportunity_id"], @link.metadata["opportunity_id"]
    end

    test "later page improvement is blocked until new article action is executed" do
      business = businesses(:suelog)
      article = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: candidate_attributes(title: "比較記事を1本作成する", action_type: "new_article_candidate")
      )
      improvement = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: candidate_attributes(title: "公開後にtitle/metaを改善する", action_type: "seo_improvement")
      )

      assert_equal true, improvement.metadata["blocked"]
      assert_equal article.id, improvement.metadata["prerequisite_action_candidate_id"]

      article.mark_executed!(executed_by: "test")
      assert_nil improvement.reload.metadata["blocked"]
      opportunity = OpportunityDiscoveryItem.find(article.metadata["opportunity_id"])
      assert_equal "一部対応", opportunity.reload.metadata["progress_status"]
    end

    test "all related actions complete resolves opportunity" do
      business = businesses(:suelog)
      article = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: candidate_attributes(title: "比較記事を1本作成する", action_type: "new_article_candidate")
      )
      link = Aicoo::ActionCandidateUpserter.call(
        business:,
        attributes: candidate_attributes(title: "関連ページから内部リンクを追加する", action_type: "seo_improvement")
      )

      article.mark_executed!(executed_by: "test")
      link.reload.mark_executed!(executed_by: "test")

      opportunity = OpportunityDiscoveryItem.find(article.metadata["opportunity_id"])
      assert_equal "解決済み", opportunity.reload.metadata["progress_status"]
      assert_equal "reviewed", opportunity.status
    end

    private

    def candidate_attributes(title:, action_type:)
      {
        title:,
        description: "「吸えログ 比較」の検索需要に対応する。",
        action_type:,
        department: "revenue",
        generation_source: "business_analyzer",
        status: "idea",
        immediate_value_yen: 80_000,
        expected_profit_yen: 30_000,
        success_probability: 0.4,
        expected_hours: 2,
        cost_yen: 0,
        metadata: {
          "opportunity_type" => "demand_without_supply",
          "opportunity_key" => "gsc:query:suelog-comparison",
          "target_keyword" => "吸えログ 比較",
          "planned_url" => "/articles/suelog-comparison",
          "concrete_task" => title,
          "execution_mode" => "content_creation",
          "data_sources_used" => %w[gsc internal]
        },
        evaluation_reason: "test",
        execution_prompt: "test"
      }
    end
  end
end
