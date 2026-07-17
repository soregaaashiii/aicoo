require "test_helper"

module Aicoo
  class SuelogArticleExpectedValueTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.data_sources.where(source_type: "gsc").destroy_all
      AicooDataSnapshot.where(source_type: "gsc").delete_all
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

    test "uses exact matching gsc query row instead of business aggregate fallback" do
      create_gsc_import <<~CSV
        query,impressions,clicks,ctr,position,page
        東通り 居酒屋 喫煙可,1200,24,0.02,11,/articles/higashidori-smoking-izakaya
        難波 喫煙 居酒屋,9000,90,0.01,18,/articles/namba-smoking-izakaya
      CSV

      result = SuelogArticleExpectedValue.call(
        business: @business,
        query: "東通り 居酒屋 喫煙可",
        gsc_inputs: business_aggregate_gsc_inputs,
        success_probability: 0.5
      )

      assert_equal "exact", result.metadata["query_match_type"]
      assert_equal "東通り 居酒屋 喫煙可", result.metadata["matched_query"]
      assert_equal 1200, result.metadata["gsc_query_impressions"]
      assert_equal 24, result.metadata["gsc_query_clicks"]
      assert_equal 1200, result.metadata.dig("gsc_inputs", "impressions")
      assert_not_equal 4308, result.metadata.dig("gsc_inputs", "impressions")
    end

    test "uses normalized matching gsc query row" do
      create_gsc_import <<~CSV
        query,impressions,clicks,ctr,position,page
        SUELOG 比較,3000,45,0.015,13,/articles/suelog-comparison
      CSV

      result = SuelogArticleExpectedValue.call(
        business: @business,
        query: "suelog 比較",
        gsc_inputs: business_aggregate_gsc_inputs,
        success_probability: 0.5
      )

      assert_equal "normalized", result.metadata["query_match_type"]
      assert_equal "SUELOG 比較", result.metadata["matched_query"]
      assert_equal 3000, result.metadata["gsc_query_impressions"]
    end

    test "uses partial matching gsc query row" do
      create_gsc_import <<~CSV
        query,impressions,clicks,ctr,position,page
        難波 喫煙 居酒屋 おすすめ,7000,35,0.005,21,/articles/namba-smoking-izakaya
      CSV

      result = SuelogArticleExpectedValue.call(
        business: @business,
        query: "難波 喫煙 居酒屋",
        gsc_inputs: business_aggregate_gsc_inputs,
        success_probability: 0.5
      )

      assert_equal "partial", result.metadata["query_match_type"]
      assert_equal "難波 喫煙 居酒屋 おすすめ", result.metadata["matched_query"]
      assert_equal 7000, result.metadata["gsc_query_impressions"]
    end

    test "uses business aggregate only as fallback when no query row matches" do
      create_gsc_import <<~CSV
        query,impressions,clicks,ctr,position,page
        梅田 喫煙 カフェ,5000,20,0.004,22,/articles/umeda-smoking-cafe
      CSV

      result = SuelogArticleExpectedValue.call(
        business: @business,
        query: "曽根崎 バー 喫煙可能",
        gsc_inputs: business_aggregate_gsc_inputs,
        success_probability: 0.5
      )

      assert_equal "fallback", result.metadata["query_match_type"]
      assert_nil result.metadata["matched_query"]
      assert_equal "gsc_query_row_not_found", result.metadata.dig("gsc_inputs", "fallback_reason")
      assert_equal 4308, result.metadata["gsc_query_impressions"]
      assert_equal 82, result.metadata["gsc_query_clicks"]
    end

    test "query specific gsc rows make higashidori and namba values differ with same fallback aggregate" do
      create_gsc_import <<~CSV
        query,impressions,clicks,ctr,position,page
        東通り 居酒屋 喫煙可,1200,24,0.02,11,/articles/higashidori-smoking-izakaya
        難波 喫煙 居酒屋,9000,90,0.01,18,/articles/namba-smoking-izakaya
      CSV

      higashidori = SuelogArticleExpectedValue.call(
        business: @business,
        query: "東通り 居酒屋 喫煙可",
        gsc_inputs: business_aggregate_gsc_inputs,
        success_probability: 0.5
      )
      namba = SuelogArticleExpectedValue.call(
        business: @business,
        query: "難波 喫煙 居酒屋",
        gsc_inputs: business_aggregate_gsc_inputs,
        success_probability: 0.5
      )

      assert_equal "exact", higashidori.metadata["query_match_type"]
      assert_equal "exact", namba.metadata["query_match_type"]
      assert_not_equal higashidori.metadata["gsc_query_impressions"], namba.metadata["gsc_query_impressions"]
      assert_not_equal higashidori.expected_profit_yen, namba.expected_profit_yen
    end

    test "uses gsc data import linked through analytics site" do
      @business.update!(gsc_site_url: "sc-domain:suelog.jp")
      site = AicooAnalyticsSite.create!(
        business: @business,
        name: "吸えログ",
        domain: "suelog.jp",
        gsc_site_url: "sc-domain:suelog.jp"
      )
      system_business = Business.find_or_create_by!(name: Business::SYSTEM_BUSINESS_NAMES.first)
      data_source = system_business.data_sources.create!(name: "GSC貼り付け", source_type: "gsc")
      data_source.data_imports.create!(
        aicoo_analytics_site: site,
        filename: "gsc_site.csv",
        imported_at: Time.current,
        processed_text: <<~CSV,
          query,clicks,impressions,ctr,position,page
          梅田 喫煙 カフェ,44,4400,0.01,14,/articles/umeda-smoking-cafe
        CSV
        row_count: 1
      )

      result = SuelogArticleExpectedValue.call(
        business: @business,
        query: "梅田 喫煙 カフェ",
        gsc_inputs: business_aggregate_gsc_inputs,
        success_probability: 0.5
      )

      assert_equal "exact", result.metadata["query_match_type"]
      assert_equal "梅田 喫煙 カフェ", result.metadata["matched_query"]
      assert_equal 4400, result.metadata["gsc_query_impressions"]
      assert_includes result.metadata["gsc_search_models"], "DataImport(aicoo_analytics_site_id)"
      assert_not_equal 4308, result.metadata["gsc_query_impressions"]
    end

    test "diagnostics reports query counts and fallback reason" do
      create_gsc_import <<~CSV
        query,impressions,clicks,ctr,position,page
        東通り 居酒屋 喫煙可,1200,24,0.02,11,/articles/higashidori-smoking-izakaya
      CSV

      diagnostics = SuelogArticleExpectedValue.new(
        business: @business,
        query: "東通り 居酒屋 喫煙可",
        gsc_inputs: business_aggregate_gsc_inputs
      ).gsc_diagnostics

      assert_equal 1, diagnostics["query_rows_count"]
      assert_equal 1, diagnostics["exact_count"]
      assert_equal "exact", diagnostics["match_type"]
      assert_nil diagnostics["fallback_reason"]
      assert_includes diagnostics["search_tables"], "data_imports"
    end

    private

    def create_gsc_import(processed_text)
      source = @business.data_sources.create!(name: "GSC", source_type: "gsc")
      source.data_imports.create!(
        filename: "gsc.csv",
        imported_at: Time.current,
        processed_text:,
        row_count: processed_text.lines.size - 1
      )
    end

    def business_aggregate_gsc_inputs
      {
        impressions: 4308,
        clicks: 82,
        ctr: 82.to_d / 4308,
        position: 12,
        landing_page: "/"
      }
    end
  end
end
