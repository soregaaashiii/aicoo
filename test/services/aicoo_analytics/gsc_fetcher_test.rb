require "test_helper"

module AicooAnalytics
  class GscFetcherTest < ActiveSupport::TestCase
    test "creates data import from gsc api response and runs pipeline" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Suelog GSC",
        site_url: "sc-domain:suelog.jp",
        fetch_days: 28
      )

      assert_difference("DataImport.count", 1) do
        result = GscFetcher.new(setting, client: FakeGscClient.new, today: Date.new(2026, 6, 19)).call

        assert_equal "gsc", result.data_import.data_source.source_type
        assert_equal 3, result.data_import.row_count
        assert_includes result.data_import.raw_text, "date,query,page,clicks,impressions,ctr,position"
        assert_includes result.data_import.raw_text, "smoking cafe"
        assert_operator result.pipeline_result.snapshot_count, :>=, 1
      end

      assert setting.reload.last_fetched_at.present?
    end

    class FakeGscClient
      def query(site_url:, start_date:, end_date:, dimensions:, row_limit:)
        {
          "rows" => [
            {
              "keys" => [ "smoking cafe", "https://example.com/smoking", "2026-06-18" ],
              "clicks" => 8,
              "impressions" => 100,
              "ctr" => 0.08,
              "position" => 4.2
            },
            {
              "keys" => [ "umeda smoking", "https://example.com/umeda", "2026-06-18" ],
              "clicks" => 3,
              "impressions" => 50,
              "ctr" => 0.06,
              "position" => 6.1
            }
          ],
          "request" => {
            "site_url" => site_url,
            "start_date" => start_date.to_s,
            "end_date" => end_date.to_s,
            "dimensions" => dimensions,
            "row_limit" => row_limit
          }
        }
      end
    end
  end
end
