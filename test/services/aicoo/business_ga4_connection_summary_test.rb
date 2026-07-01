require "test_helper"

module Aicoo
  class BusinessGa4ConnectionSummaryTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      AnalyticsFetchRun.delete_all
      AnalyticsSourceSetting.delete_all
      AicooAnalyticsSite.delete_all
    end

    test "summarizes ga4 property fetch count and last error" do
      site = AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        ga4_property_id: "properties/999",
        authentication_mode: "shared"
      )
      setting = site.ga4_setting
      setting.analytics_fetch_runs.create!(
        status: "success",
        source_type: "ga4",
        snapshot_count: 12,
        started_at: 1.hour.ago,
        finished_at: 1.hour.ago
      )
      setting.analytics_fetch_runs.create!(
        status: "failed",
        source_type: "ga4",
        error_message: "invalid property",
        started_at: Time.current,
        finished_at: Time.current
      )

      summary = BusinessGa4ConnectionSummary.new(@business).call

      assert summary.configured
      assert_equal "properties/999", summary.property_id
      assert_equal 0, summary.last_count
      assert_equal "invalid property", summary.last_error
    end

    test "summarizes business named ga4 setting when analytics site is missing" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "#{@business.name} GA4",
        property_id: "536889590",
        enabled: true,
        authentication_mode: "shared"
      )
      setting.analytics_fetch_runs.create!(
        status: "failed",
        source_type: "ga4",
        snapshot_count: 0,
        error_message: "invalid_grant",
        started_at: Time.current,
        finished_at: Time.current
      )

      summary = BusinessGa4ConnectionSummary.new(@business).call

      assert summary.configured
      assert_equal "536889590", summary.property_id
      assert_equal "invalid_grant", summary.last_error
    end
  end
end
