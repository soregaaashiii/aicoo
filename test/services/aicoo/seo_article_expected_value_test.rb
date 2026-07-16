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

    test "marks insufficient data instead of substituting a cap value" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "入力不足の記事候補",
        action_type: "seo_article",
        success_probability: 0.5,
        metadata: {
          "impressions" => 10_000,
          "current_ctr" => 0.01,
          "target_ctr" => 0.03
        }
      )

      result = SeoArticleExpectedValue.call(candidate)

      assert_equal 0, result.final_expected_value_yen
      assert_equal "insufficient_data", result.metadata["calculation_status"]
      assert_equal true, result.metadata["review_required"]
      assert_includes result.metadata.dig("seo_article_value_model", "missing_inputs"), "conversion_rate"
      assert_includes result.metadata.dig("seo_article_value_model", "missing_inputs"), "profit_per_conversion_yen"
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
