require "test_helper"

class GscImportServiceTest < ActiveSupport::TestCase
  test "imports query rows into a gsc data import" do
    business = businesses(:suelog)
    business.update!(gsc_site_url: "sc-domain:suelog.jp")

    service = GscImportService.new(business, client: FakeGscClient.new, today: Date.new(2026, 6, 16))

    assert_difference -> { DataImport.count }, 1 do
      result = service.call

      assert_equal "gsc", result.data_source.source_type
      assert_equal 2, result.data_import.row_count
      assert_equal "gsc_queries_2026-05-19_2026-06-15.csv", result.data_import.filename
      assert_includes result.data_import.processed_text, "query,clicks,impressions,ctr,position"
      assert_includes result.data_import.processed_text, "nakazakicho smoking"
      assert_includes result.data_import.raw_text, "responseAggregationType"
    end
  end

  test "requires business gsc site url" do
    business = businesses(:suelog)
    business.update!(gsc_site_url: nil)

    error = assert_raises(GscSearchAnalyticsClient::Error) do
      GscImportService.new(business, client: FakeGscClient.new).call
    end

    assert_equal "Business gsc_site_url is not set.", error.message
  end

  class FakeGscClient
    def query(site_url:, start_date:, end_date:, dimensions: [ "query" ], row_limit: 1_000)
      {
        "rows" => [
          { "keys" => [ "nakazakicho smoking" ], "clicks" => 10, "impressions" => 100, "ctr" => 0.1, "position" => 3.2 },
          { "keys" => [ "umeda smoking cafe" ], "clicks" => 5, "impressions" => 80, "ctr" => 0.0625, "position" => 6.4 }
        ],
        "responseAggregationType" => "byProperty",
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
