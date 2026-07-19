require "test_helper"
require "set"

module Aicoo
  class SuelogGa4DataIntegrityCheckTest < ActiveSupport::TestCase
    SUELOG_PROPERTY_ID = "536889590"

    setup do
      @business = businesses(:suelog)
      @setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "吸えログ GA4",
        property_id: SUELOG_PROPERTY_ID,
        enabled: true
      )
      BusinessDataSourceSetting.create!(
        business: @business,
        source_key: "ga4",
        enabled: true,
        connection_status: "linked",
        metadata: { "connection_fields" => { "property_id" => SUELOG_PROPERTY_ID } }
      )
    end

    test "returns fail when oauth is unusable" do
      check = build_check(oauth_usable: false, rows: [ article_row ])

      result = check.call

      assert_equal "fail", result.integrity_status
      assert_includes result.blocking_reasons, "oauth_expired_or_unusable"
    end

    test "returns fail when mixed business rows are present" do
      check = build_check(rows: [ article_row.merge("business_id" => @business.id), article_row.merge("business_id" => @business.id + 100) ])

      result = check.call

      assert_equal "fail", result.integrity_status
      assert_equal 1, result.mixed_business_row_count
      assert_includes result.blocking_reasons, "mixed_business_data"
    end

    test "returns warning when valid rows exist but some articles are unmatched" do
      check = build_check(
        rows: [ article_row ],
        article_match_summary: {
          matched_article_ids: Set.new([ 1 ]),
          article_count: 2,
          unmatched_article_count: 1
        }
      )

      result = check.call

      assert_equal "warning", result.integrity_status
      assert_equal 1, result.article_row_count
      assert_equal 1, result.ga4_matched_articles
      assert_equal 50.0, result.ga4_article_match_rate
    end

    test "returns pass when oauth rows property and articles are healthy" do
      check = build_check(rows: [ article_row ])

      result = check.call

      assert_equal "pass", result.integrity_status
      assert_empty result.blocking_reasons
    end

    private

    def build_check(rows:, oauth_usable: true, article_match_summary: nil)
      check = SuelogGa4DataIntegrityCheck.new(business: @business, expected_business_id: @business.id)
      setting = @setting
      summary = article_match_summary || {
        matched_article_ids: Set.new([ 1 ]),
        article_count: 1,
        unmatched_article_count: 0
      }
      check.define_singleton_method(:setting) { setting }
      check.define_singleton_method(:oauth_usable?) { oauth_usable }
      check.define_singleton_method(:latest_fetch_status) { "success" }
      check.define_singleton_method(:latest_success_at) { Time.current.iso8601 }
      check.define_singleton_method(:latest_failure_at) { nil }
      check.define_singleton_method(:rows) { rows }
      check.define_singleton_method(:article_match_summary) { summary }
      check
    end

    def article_row
      {
        "business_id" => @business.id,
        "property_id" => SUELOG_PROPERTY_ID,
        "hostName" => "suelog.jp",
        "normalized_page" => "/articles/umeda-smoking-cafe",
        "imported_at" => Time.current.iso8601
      }
    end
  end
end
