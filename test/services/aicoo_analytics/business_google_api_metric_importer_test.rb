require "test_helper"

module AicooAnalytics
  class BusinessGoogleApiMetricImporterTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      AnalyticsFetchRun.delete_all
      BusinessMetricDaily.delete_all
      AnalyticsSourceSetting.delete_all
      AicooAnalyticsSite.delete_all
      AicooGoogleCredential.delete_all
      @business.update!(gsc_site_url: "sc-domain:suelog.test")
      @credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
      @site = AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/123",
        authentication_mode: "shared"
      )
      @site.gsc_setting.update!(google_credential: @credential)
      @site.ga4_setting.update!(google_credential: @credential)
    end

    test "fetches google api data and writes business metric daily records directly" do
      assert_difference("BusinessMetricDaily.count", 2) do
        result = BusinessGoogleApiMetricImporter.new(
          business: @business,
          today: Date.new(2026, 6, 28),
          gsc_client: FakeGscClient.new,
          ga4_client: FakeGa4Client.new
        ).call

        assert_equal 2, result.metric_count
        assert_equal %w[GSC GA4], result.imported_source_labels
        assert_equal @credential.id, result.credential_snapshots.dig("gsc", "record_id")
        assert_equal @credential.id, result.credential_snapshots.dig("ga4", "record_id")
        assert_equal "client", result.credential_snapshots.dig("gsc", "client_id")
        ga4_result = result.source_results.find { |row| row[:source] == "ga4" }
        assert_equal 2, ga4_result[:api_row_count]
        assert_equal 2, ga4_result[:saved_day_count]
        assert_equal 60, ga4_result[:totals]["sessions"]
        assert_equal 140, ga4_result[:totals]["pageviews"]
        assert_equal "properties/123", ga4_result[:identifier]
      end

      first_metric = BusinessMetricDaily.find_by!(business: @business, recorded_on: Date.new(2026, 6, 26))
      second_metric = BusinessMetricDaily.find_by!(business: @business, recorded_on: Date.new(2026, 6, 27))

      assert_equal 100, first_metric.impressions
      assert_equal 10, first_metric.clicks
      assert_equal 4.5.to_d, first_metric.average_position
      assert_equal 20, first_metric.sessions
      assert_equal 15, first_metric.users
      assert_equal 50, first_metric.pageviews
      assert_equal 90, first_metric.average_engagement_time_seconds
      assert_equal 0.6.to_d, first_metric.engagement_rate
      assert_equal 2, first_metric.conversions

      assert_equal 200, second_metric.impressions
      assert_equal 30, second_metric.clicks
      assert_equal 3.2.to_d, second_metric.average_position
      assert_equal 40, second_metric.sessions
      assert_equal 30, second_metric.users
      assert_equal 90, second_metric.pageviews
      assert_equal 120, second_metric.average_engagement_time_seconds
      assert_equal 0.7.to_d, second_metric.engagement_rate
      assert_equal 5, second_metric.conversions

      assert_equal 2, AnalyticsFetchRun.where(status: "success").count
      assert @site.gsc_setting.reload.last_fetched_at.present?
      assert @site.ga4_setting.reload.last_fetched_at.present?
    end

    test "can import only gsc" do
      result = BusinessGoogleApiMetricImporter.new(
        business: @business,
        today: Date.new(2026, 6, 28),
        source_types: %w[gsc],
        gsc_client: FakeGscClient.new,
        ga4_client: FakeGa4Client.new
      ).call

      metric = BusinessMetricDaily.find_by!(business: @business, recorded_on: Date.new(2026, 6, 26))
      assert_equal 10, metric.clicks
      assert_equal 0, metric.sessions
      assert_equal %w[GSC], result.imported_source_labels
    end

    test "adds a warning when ga4 property id looks like measurement id" do
      @site.ga4_setting.update!(property_id: "G-E5KCHJTFVP")

      result = BusinessGoogleApiMetricImporter.new(
        business: @business,
        today: Date.new(2026, 6, 28),
        source_types: %w[ga4],
        ga4_client: FakeGa4Client.new
      ).call

      ga4_result = result.source_results.find { |row| row[:source] == "ga4" }
      assert_includes ga4_result[:property_id_warning], "測定ID"
    end

    class FakeGscClient
      def query(site_url:, start_date:, end_date:, dimensions:, row_limit:)
        {
          "rows" => [
            { "keys" => [ "2026-06-26" ], "clicks" => 10, "impressions" => 100, "ctr" => 0.1, "position" => 4.5 },
            { "keys" => [ "2026-06-27" ], "clicks" => 30, "impressions" => 200, "ctr" => 0.15, "position" => 3.2 }
          ],
          "request" => { "site_url" => site_url, "start_date" => start_date.to_s, "end_date" => end_date.to_s, "dimensions" => dimensions, "row_limit" => row_limit }
        }
      end
    end

    class FakeGa4Client
      def run_report(property_id:, start_date:, end_date:, dimensions:, metrics:, limit:)
        {
          "rows" => [
            {
              "dimensionValues" => [ { "value" => "20260626" } ],
              "metricValues" => [
                { "value" => "20" },
                { "value" => "15" },
                { "value" => "50" },
                { "value" => "90" },
                { "value" => "0.6" },
                { "value" => "2" },
                { "value" => "100" }
              ]
            },
            {
              "dimensionValues" => [ { "value" => "20260627" } ],
              "metricValues" => [
                { "value" => "40" },
                { "value" => "30" },
                { "value" => "90" },
                { "value" => "120" },
                { "value" => "0.7" },
                { "value" => "5" },
                { "value" => "180" }
              ]
            }
          ],
          "request" => { "property_id" => property_id, "start_date" => start_date.to_s, "end_date" => end_date.to_s, "dimensions" => dimensions, "metrics" => metrics, "limit" => limit }
        }
      end
    end
  end
end
