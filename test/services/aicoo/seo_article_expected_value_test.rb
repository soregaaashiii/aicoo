require "test_helper"

module Aicoo
  class SeoArticleExpectedValueTest < ActiveSupport::TestCase
    test "calculates seo article value from incremental clicks only" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "東通り 居酒屋 喫煙可の記事を作る",
        action_type: "seo_article",
        success_probability: 0.5,
        immediate_value_yen: 9_000_000,
        expected_learning_value_yen: 8_000_000,
        final_expected_value_yen: 9_000_000,
        metadata: {
          "impressions" => 10_000,
          "current_ctr" => 0.01,
          "target_ctr" => 0.03,
          "conversion_rate" => 0.02,
          "profit_per_conversion" => 1_000
        }
      )

      result = SeoArticleExpectedValue.call(candidate)

      assert_equal 2_000, result.raw_expected_value_yen
      assert_equal 2_000, result.final_expected_value_yen
      assert_equal %w[learning judge business_expected_value], result.metadata.dig("seo_article_value_model", "excluded_value_sources")
    end

    test "does not cap seo article value without revenue events" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "梅田 喫煙 カフェの記事を作る",
        action_type: "new_article_candidate",
        success_probability: 1.0,
        metadata: {
          "impressions" => 10_000_000,
          "current_ctr" => 0.01,
          "target_ctr" => 0.50,
          "conversion_rate" => 1.0,
          "profit_per_conversion" => 50_000
        }
      )

      result = SeoArticleExpectedValue.call(candidate)

      assert result.raw_expected_value_yen > 1_000_000
      assert_equal result.raw_expected_value_yen, result.final_expected_value_yen
      assert result.final_expected_value_yen > 1_000_000
      assert_nil result.metadata["seo_expected_value_cap"]
      assert_equal false, result.metadata.dig("seo_article_value_model", "cap_applied")
    end

    test "uses existing assumptions instead of returning zero when cv and profit are missing" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "仮定値を使う記事候補",
        action_type: "seo_article",
        success_probability: 0.5,
        metadata: {
          "impressions" => 10_000,
          "current_ctr" => 0.01,
          "target_ctr" => 0.03
        }
      )

      result = SeoArticleExpectedValue.call(candidate)

      assert result.final_expected_value_yen.positive?
      assert_equal "estimated", result.metadata["calculation_status"]
      assert_equal true, result.metadata["review_required"]
      assert_equal true, result.metadata["assumption_used"]
      assert_includes result.metadata["assumed_fields"], "conversion_rate"
      assert_includes result.metadata["assumed_fields"], "profit_per_conversion_yen"
      assert_empty result.metadata.dig("seo_article_value_model", "missing_inputs")
    end

    test "marks insufficient data only when incremental clicks cannot be estimated" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "本当に入力不足の記事候補",
        action_type: "seo_article",
        metadata: {}
      )

      result = SeoArticleExpectedValue.call(candidate)

      assert_equal 0, result.final_expected_value_yen
      assert_equal "insufficient_data", result.metadata["calculation_status"]
      assert_equal true, result.metadata["review_required"]
      assert_includes result.metadata.dig("seo_article_value_model", "missing_inputs"), "estimated_incremental_clicks"
    end

    test "recovers query from title and uses business serp keyword metrics" do
      business = businesses(:suelog)
      business.business_serp_keywords.create!(
        keyword: "東通り 居酒屋 喫煙可",
        normalized_keyword: BusinessSerpKeyword.normalize("東通り 居酒屋 喫煙可"),
        source: "gsc",
        status: "active",
        latest_impressions: 10_000,
        latest_ctr: 0.01,
        latest_rank: 12,
        priority_score: 80
      )
      candidate = ActionCandidate.new(
        business:,
        title: "「東通り 居酒屋 喫煙可」向けの新規記事候補を作成する",
        action_type: "new_article_candidate",
        success_probability: 0.5,
        metadata: {}
      )

      result = SeoArticleExpectedValue.call(candidate)

      assert result.final_expected_value_yen.positive?
      assert_equal "東通り 居酒屋 喫煙可", result.metadata["source_query"]
      assert_equal true, result.metadata["query_recovered"]
      assert_equal "business_serp_keywords.latest_impressions", result.metadata.dig("input_sources", "impressions")
      assert_equal "business_serp_keywords.latest_ctr", result.metadata.dig("input_sources", "current_ctr")
      assert_equal "estimated", result.metadata["calculation_status"]
      assert_equal true, result.metadata["review_required"]
      assert_includes result.metadata["assumed_fields"], "target_ctr"
      assert_includes result.metadata["assumed_fields"], "conversion_rate"
      assert_includes result.metadata["assumed_fields"], "profit_per_conversion_yen"
    end

    test "normalizes percent success probability values" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "成功率単位を正規化する記事候補",
        action_type: "new_article_candidate",
        metadata: {
          "impressions" => 10_000,
          "current_ctr" => 0.01,
          "target_ctr" => 0.03,
          "conversion_rate" => 0.02,
          "profit_per_conversion" => 1_000,
          "success_probability" => 36
        }
      )

      result = SeoArticleExpectedValue.call(candidate)

      assert_equal 0.36, result.metadata["success_probability"]
      assert_equal 1_440, result.final_expected_value_yen
    end

    test "meta evaluator does not add judge learning or business total value to seo article" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "吸えログ 比較の記事を作る",
        action_type: "seo_article",
        success_probability: 0.5,
        expected_total_value_yen: 5_000_000,
        expected_learning_value_yen: 2_000_000,
        metadata: {
          "impressions" => 10_000,
          "current_ctr" => 0.01,
          "target_ctr" => 0.03,
          "conversion_rate" => 0.02,
          "profit_per_conversion" => 1_000
        }
      )

      result = AicooMetaEvaluator::MetaEvaluator.new(candidate).call

      assert_equal 2_000, result.final_expected_value_yen
      assert_equal %w[learning judge business_expected_value], result.evaluator_breakdown.first.fetch("excluded_value_sources")
    end
  end
end
