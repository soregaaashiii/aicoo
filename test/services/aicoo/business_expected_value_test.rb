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

    test "does not clamp evidence backed value over one million yen" do
      create_candidate!(
        title: "根拠ある大型候補",
        value: 2_000_000,
        metadata: {
          "query" => "大型 クエリ",
          "evidence" => {
            "impressions" => 2_000_000,
            "current_ctr" => 0.01,
            "benchmark_ctr" => 0.08,
            "conversion_rate" => 0.05
          },
          "value_model" => {
            "evidence" => { "profit_per_conversion" => 10_000 },
            "confidence" => 1
          }
        }
      )

      result = BusinessExpectedValue.call(@business)

      assert_operator result.expected_revenue_value_yen, :>, 1_000_000
      candidate = @business.action_candidates.active_for_ranking.first
      assert_equal 2_000_000, candidate.metadata.dig("business_value_model", "raw_expected_value_yen")
      assert_equal 2_000_000, candidate.metadata.dig("business_value_model", "final_expected_value_yen")
      assert candidate.metadata.dig("business_value_model", "anomaly_detected")
    end

    test "recalculates value when GSC traffic limit is lower than raw value" do
      create_candidate!(
        title: "流入上限が小さい候補",
        value: 5_000_000,
        metadata: {
          "query" => "小さい クエリ",
          "evidence" => {
            "impressions" => 1_000,
            "current_ctr" => 0.01,
            "benchmark_ctr" => 0.03,
            "conversion_rate" => 0.1
          },
          "value_model" => {
            "evidence" => { "profit_per_conversion" => 1_000 },
            "confidence" => 1
          }
        }
      )

      result = BusinessExpectedValue.call(@business)

      assert_equal 2_000, result.expected_revenue_value_yen
      assert_operator result.market_limit_adjustment_yen, :>, 0
      candidate = @business.action_candidates.active_for_ranking.first
      assert_equal 2_000, candidate.metadata.dig("business_value_model", "final_expected_value_yen")
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

    test "launched business uses base plus action opportunity value" do
      @business.revenue_events.delete_all
      @business.business_metric_dailies.delete_all
      @business.revenue_events.create!(
        amount: 50_000,
        event_type: "profit",
        occurred_on: Date.current
      )
      create_candidate!(
        title: "吸えログの改善施策",
        value: 20_000,
        metadata: { "query" => "吸えログ 改善" }
      )

      result = BusinessExpectedValue.call(@business)

      assert_equal 50_000, result.base_business_value_yen
      assert_equal 20_000, result.action_opportunity_value_yen
      assert_equal 70_000, result.expected_total_value_yen
      assert_equal "existing_business_base_plus_actions", result.calculation_method
      assert_equal "existing_business_base_plus_actions", @business.reload.metadata.dig("business_value_model", "model_name")
    end

    test "suelog existing business is detected without fixed business id" do
      business = Business.create!(
        name: "大阪喫煙メディア",
        status: "launched",
        business_type: "seo_media",
        project_key: "suelog"
      )
      business.business_metric_dailies.create!(
        recorded_on: Date.current,
        clicks: 100,
        phone_clicks: 2,
        map_clicks: 3,
        affiliate_clicks: 1
      )

      BusinessExpectedValue.call(business)

      assert_equal "suelog_existing_business", business.reload.metadata.dig("business_value_model", "base_business_value", "source_model")
    end

    test "uses proxy weighted conversion clicks when measured profit is absent" do
      @business.revenue_events.delete_all
      @business.business_metric_dailies.delete_all
      @business.business_metric_dailies.create!(
        recorded_on: Date.current,
        clicks: 1_000,
        impressions: 10_000,
        sessions: 800,
        pageviews: 1_200,
        users: 500,
        phone_clicks: 2,
        map_clicks: 3,
        affiliate_clicks: 1
      )

      result = BusinessExpectedValue.call(@business)

      assert_equal 64, result.base_business_value_yen
      assert_equal "business_metric_dailies_proxy_weighted_clicks", result.base_business_value.source
      assert_match(/BusinessMetricDaily/, result.base_business_value.double_count_prevention)
    end

    test "does not monetize gsc or ga4 traffic without revenue or conversion clicks" do
      @business.revenue_events.delete_all
      @business.business_metric_dailies.delete_all
      @business.business_metric_dailies.create!(
        recorded_on: Date.current,
        clicks: 500,
        impressions: 20_000,
        sessions: 700,
        pageviews: 1_400,
        users: 600
      )

      result = BusinessExpectedValue.call(@business)

      assert_equal 0, result.base_business_value_yen
      assert_equal "insufficient_monetization_data", result.base_business_value.calculation_status
      assert_equal false, result.base_business_value.gsc_inputs["used_for_profit"]
      assert_equal false, result.base_business_value.ga4_inputs["used_for_profit"]
    end

    test "terminal statuses are not included in action opportunity value" do
      create_candidate!(title: "有効施策", value: 10_000, metadata: { "query" => "有効" })
      create_candidate!(title: "却下施策", value: 90_000, metadata: { "query" => "却下" }).update!(status: "rejected")

      result = BusinessExpectedValue.call(@business)

      assert_equal 10_000, result.action_opportunity_value_yen
    end

    test "read only calculation accepts preloaded candidates without persisting metadata" do
      @business = businesses(:cards)
      candidate = create_candidate!(title: "Today read only expected value", value: 12_000)
      business = candidate.business.reload
      original_business_metadata = business.metadata.deep_dup
      original_candidate_metadata = candidate.reload.metadata.deep_dup

      result = BusinessExpectedValue.call(
        business,
        candidates: [ candidate ],
        persist: false
      )

      assert_operator result.expected_total_value_yen, :>=, 0
      assert_equal original_business_metadata, business.reload.metadata
      assert_equal original_candidate_metadata, candidate.reload.metadata
    end

    test "exploring business expected value is not fixed capped" do
      business = Business.create!(
        name: "大型SERP発見事業",
        status: "exploring",
        business_type: "exploration",
        created_by_aicoo: true,
        metadata: {
          "estimated_90d_profit_yen" => 10_000_000,
          "validation_success_probability" => 0.4,
          "validation_cost_yen" => 300_000
        }
      )

      result = BusinessExpectedValue.call(business)

      assert_equal 3_700_000, result.expected_total_value_yen
      assert_equal 3_700_000, business.reload.metadata.dig("business_value_model", "new_business_value", "final_expected_value_yen")
    end

    test "business expected value has no fixed cap constants" do
      assert_not Aicoo::BusinessExpectedValue.const_defined?(:ACTION_CAP_YEN)
      assert_not Aicoo::BusinessExpectedValue.const_defined?(:OPPORTUNITY_CAP_YEN)
      assert_not Aicoo::BusinessExpectedValue.const_defined?(:BUSINESS_SHORT_TERM_CAP_YEN)
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
