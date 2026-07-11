require "test_helper"

module Aicoo
  class BusinessExpectedValueTest < ActiveSupport::TestCase
    setup do
      ActionCandidate.update_all(status: "done")
      @business = businesses(:suelog)
    end

    test "does not simply sum title and article candidates for same keyword" do
      first = create_candidate!(
        title: "梅田 喫煙 居酒屋のtitle/metaを改善する",
        value: 180_000,
        metadata: { "query" => "梅田 喫煙 居酒屋", "target_url" => "https://suelog.jp/articles/umeda-smoking-izakaya" }
      )
      second = create_candidate!(
        title: "梅田 喫煙 居酒屋の記事を作成する",
        action_type: "new_article_candidate",
        value: 160_000,
        metadata: { "query" => "梅田 喫煙 居酒屋", "recommended_slug" => "umeda-smoking-izakaya" }
      )

      result = BusinessExpectedValue.call(@business)

      assert_equal 1, result.unique_opportunity_count
      assert_equal 1, result.duplicate_candidate_count
      assert_operator result.expected_revenue_value_yen, :<, first.expected_profit_yen + second.expected_profit_yen
      assert_equal [ second.id ], first.reload.metadata.dig("business_value_model", "duplicate_candidates")
    end

    test "caps single action and business short term expected value" do
      6.times do |index|
        create_candidate!(
          title: "高額候補 #{index}",
          value: 900_000,
          metadata: { "query" => "高額 クエリ #{index}" }
        )
      end

      result = BusinessExpectedValue.call(@business)

      assert_operator result.cap_adjustment_yen, :>, 0
      assert_operator result.expected_revenue_value_yen, :<=, BusinessExpectedValue::BUSINESS_SHORT_TERM_CAP_YEN
      capped_candidate = @business.action_candidates.active_for_ranking.first
      assert_equal 900_000, capped_candidate.metadata.dig("business_value_model", "raw_expected_value_yen")
      assert_equal BusinessExpectedValue::ACTION_CAP_YEN, capped_candidate.metadata.dig("business_value_model", "capped_expected_value_yen")
    end

    test "exploring business gets fallback value instead of zero" do
      business = Business.create!(
        name: "SERP発見テスト事業",
        status: "exploring",
        business_type: "exploration",
        created_by_aicoo: true
      )

      result = BusinessExpectedValue.call(business)

      assert_equal 30_000, result.new_business_value.estimated_90d_profit_yen
      assert_equal 5_000, result.new_business_value.validation_cost_yen
      assert_equal(-500, result.expected_total_value_yen)
      assert_equal "new_business_fallback_standard_90d", result.calculation_method
      assert_equal(-500, business.reload.metadata.dig("business_value_model", "new_business_value", "final_expected_value_yen"))
    end

    test "exploring business uses metadata when available" do
      business = Business.create!(
        name: "SERP発見メタデータ事業",
        status: "exploring",
        business_type: "exploration",
        created_by_aicoo: true,
        metadata: {
          "estimated_90d_profit_yen" => 200_000,
          "validation_success_probability" => 0.25,
          "validation_cost_yen" => 20_000
        }
      )

      result = BusinessExpectedValue.call(business)

      assert_equal 30_000, result.expected_total_value_yen
      assert_equal "new_business_metadata", result.calculation_method
    end

    private

    def create_candidate!(title:, value:, action_type: "seo_improvement", metadata: {})
      ActionCandidate.create!(
        business: @business,
        title:,
        status: "approved",
        action_type:,
        generation_source: "business_analyzer",
        immediate_value_yen: value,
        success_probability: 1,
        expected_hours: 1,
        cost_yen: 0,
        metadata: {
          "execution_mode" => "manual_operation",
          "concrete_task" => title,
          "action_plan" => {
            "summary" => title,
            "target" => metadata["target_url"].presence || metadata["query"].presence || title,
            "owner_next_step" => "実行する",
            "execution_steps" => [ "実行する" ],
            "execution_units" => [ { "label" => title } ]
          }
        }.merge(metadata)
          .merge(
            "value_model" => {
              "raw_expected_value_yen" => value,
              "confidence" => 1,
              "evidence_level" => "high"
            }.merge(metadata.fetch("value_model", {}))
          )
      )
    end
  end
end
