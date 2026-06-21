require "test_helper"

module AicooAnalytics
  class Ga4FetcherTest < ActiveSupport::TestCase
    test "creates data import from ga4 api response and runs pipeline" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Suelog GA4",
        property_id: "123456789",
        fetch_days: 28
      )

      assert_difference("DataImport.count", 1) do
        result = Ga4Fetcher.new(setting, client: FakeGa4Client.new, today: Date.new(2026, 6, 19)).call

        assert_equal "ga4", result.data_import.data_source.source_type
        assert_equal 3, result.data_import.row_count
        assert_includes result.data_import.raw_text, "date,pagePath,screenPageViews,activeUsers,sessions,eventCount"
        assert_includes result.data_import.raw_text, "/smoking"
        assert_operator result.pipeline_result.snapshot_count, :>=, 1
      end

      assert setting.reload.last_fetched_at.present?
    end

    class FakeGa4Client
      def run_report(property_id:, start_date:, end_date:)
        {
          "rows" => [
            {
              "dimensionValues" => [ { "value" => "20260618" }, { "value" => "/smoking" } ],
              "metricValues" => [ { "value" => "120" }, { "value" => "40" }, { "value" => "55" }, { "value" => "9" } ]
            },
            {
              "dimensionValues" => [ { "value" => "20260618" }, { "value" => "/umeda" } ],
              "metricValues" => [ { "value" => "80" }, { "value" => "30" }, { "value" => "35" }, { "value" => "4" } ]
            }
          ],
          "request" => {
            "property_id" => property_id,
            "start_date" => start_date.to_s,
            "end_date" => end_date.to_s
          }
        }
      end
    end
  end
end
