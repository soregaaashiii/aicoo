require "test_helper"

module Aicoo
  class SuelogArticleExpectedValueTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.business_metric_dailies.delete_all
      @business.business_metric_dailies.create!(
        recorded_on: Date.current,
        impressions: 20_000,
        clicks: 1_000,
        sessions: 900,
        pageviews: 1_500,
        users: 700,
        phone_clicks: 30,
        map_clicks: 60,
        affiliate_clicks: 10,
        average_engagement_time_seconds: 80
      )
    end

    test "suelog article values differ by search demand and current performance" do
      rows = [
        [ "東通り 居酒屋 喫煙可", 20_000, 120, 0.006, 12 ],
        [ "曽根崎 バー 喫煙可能", 8_000, 80, 0.010, 8 ],
        [ "梅田 喫煙 居酒屋", 14_000, 210, 0.015, 9 ],
        [ "難波 喫煙 居酒屋", 11_000, 55, 0.005, 18 ],
        [ "梅田 喫煙 カフェ", 5_000, 25, 0.005, 22 ]
      ]

      values = rows.map do |query, impressions, clicks, ctr, position|
        SuelogArticleExpectedValue.call(
          business: @business,
          query:,
          gsc_inputs: { impressions:, clicks:, ctr:, position: },
          ga4_inputs: { pageviews: impressions / 10, active_users: clicks, engagement_seconds: 75 },
          shopclick_inputs: { recent_shop_clicks: clicks / 2, matched_shop_count: 5 },
          success_probability: 0.48
        ).expected_profit_yen
      end

      assert_operator values.uniq.size, :>, 1
      assert_operator values.first, :>, values.last
    end

    test "stores gsc ga4 shopclick and business metric inputs in metadata" do
      result = SuelogArticleExpectedValue.call(
        business: @business,
        query: "梅田 喫煙 居酒屋",
        gsc_inputs: { impressions: 10_000, clicks: 100, ctr: 0.01, position: 11, landing_page: "/umeda" },
        ga4_inputs: { pageviews: 600, active_users: 300, engagement_seconds: 92 },
        shopclick_inputs: { recent_shop_clicks: 120, matched_shop_count: 8, lookback_days: 90 },
        success_probability: 0.48
      )

      assert_equal "suelog_article", result.metadata.dig("value_model", "name")
      assert_equal 10_000, result.metadata.dig("gsc_inputs", "impressions")
      assert_equal 600, result.metadata.dig("ga4_inputs", "pageviews")
      assert_equal 120, result.metadata.dig("shopclick_inputs", "recent_shop_clicks")
      assert_equal 1_000, result.metadata.dig("business_metric_inputs", "business_clicks_90d")
      assert result.metadata["estimated_incremental_clicks"].positive?
      assert result.metadata["estimated_shop_visits"].positive?
      assert result.metadata.key?("estimated_booking_clicks")
      assert_equal result.expected_profit_yen, result.metadata["expected_profit_yen"]
    end
  end
end
