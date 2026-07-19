require "test_helper"

module Aicoo
  class SuelogGa4ResyncTest < ActiveSupport::TestCase
    SUELOG_PROPERTY_ID = "536889590"

    setup do
      @business = businesses(:suelog)
      @business.update!(metadata: @business.metadata.merge("public_url" => "https://suelog.jp"))
      @credential = AicooGoogleCredential.create!(
        name: "Suelog Google",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh",
        access_token: "access",
        token_expires_at: 1.hour.from_now
      )
      @site = AicooAnalyticsSite.create!(
        business: @business,
        name: "吸えログ",
        domain: "suelog.jp",
        public_url: "https://suelog.jp",
        ga4_property_id: SUELOG_PROPERTY_ID,
        authentication_mode: "shared"
      )
      @setting = @site.ga4_setting
      @setting.update!(google_credential: @credential)
      BusinessDataSourceSetting.create!(
        business: @business,
        source_key: "ga4",
        enabled: true,
        connection_status: "linked",
        metadata: {
          "connection_fields" => {
            "property_id" => SUELOG_PROPERTY_ID,
            "host" => "suelog.jp"
          }
        }
      )
    end

    test "does not resync when oauth is unusable" do
      @credential.update!(refresh_token: nil)
      @setting.update!(refresh_token: nil)

      assert_no_difference("DataImport.count") do
        result = SuelogGa4Resync.call(
          business: @business,
          apply: true,
          client: FakeGa4Client.new,
          access_token: "access",
          expected_business_id: @business.id
        )

        assert_not result.resync_allowed
        assert_includes result.blocking_reasons, "refresh_token_not_found"
      end
    end

    test "dry-run does not persist data" do
      assert_no_difference("DataImport.count") do
        result = SuelogGa4Resync.call(
          business: @business,
          apply: false,
          client: FakeGa4Client.new,
          access_token: "access",
          expected_business_id: @business.id
        )

        assert_equal "dry-run", result.mode
        assert_equal 1, result.article_row_count
        assert_equal 1, result.lp_row_count
        assert_equal 1, result.excluded_counts["wrong_host"]
      end
    end

    test "apply saves only suelog host rows under the suelog business" do
      assert_difference("DataImport.count", 1) do
        result = SuelogGa4Resync.call(
          business: @business,
          apply: true,
          client: FakeGa4Client.new,
          access_token: "access",
          expected_business_id: @business.id
        )

        assert result.resync_allowed
        assert_equal 2, result.saved_row_count
        assert_equal 1, result.article_row_count
        assert_equal 1, result.excluded_counts["wrong_host"]
        assert result.data_import_id.present?
      end

      data_import = DataImport.recent.first
      assert_equal @business.id, data_import.business.id
      assert_equal @site.id, data_import.aicoo_analytics_site_id
      assert_includes data_import.raw_text, "/articles/umeda-smoking-cafe"
      assert_includes data_import.raw_text, "/lp"
      assert_not_includes data_import.raw_text, "aicoo.onrender.com"
    end

    test "accepts blank host when page location belongs to suelog" do
      result = SuelogGa4Resync.call(
        business: @business,
        apply: false,
        client: FakeGa4Client.new(rows: [
          FakeGa4Client.row("20260717", "/articles/namba-smoking-izakaya", "", 80, page_location: "https://suelog.jp/articles/namba-smoking-izakaya")
        ]),
        access_token: "access",
        expected_business_id: @business.id
      )

      assert_equal 1, result.saved_row_count
      assert_equal 1, result.article_row_count
      assert_equal({ "page_location_host_match" => 1 }, result.accepted_reason_counts.stringify_keys)
      assert_empty result.excluded_counts
      assert_equal "suelog.jp", result.row_diagnostics.first.fetch(:normalized_host)
    end

    test "accepts blank host without page location only when business property and setting are verified" do
      result = SuelogGa4Resync.call(
        business: @business,
        apply: false,
        client: FakeGa4Client.new(rows: [
          FakeGa4Client.row("20260717", "/articles/higashidori-smoking", "(not set)", 60)
        ]),
        access_token: "access",
        expected_business_id: @business.id
      )

      assert_equal 1, result.saved_row_count
      assert_equal 1, result.article_row_count
      assert_equal({ "property_business_setting_match_no_host" => 1 }, result.accepted_reason_counts.stringify_keys)
      assert_empty result.excluded_counts
    end

    class FakeGa4Client
      def initialize(rows: nil)
        @rows = rows
      end

      def run_report(property_id:, start_date:, end_date:, dimensions:, metrics:, limit:)
        {
          "rows" => @rows || [
            row("20260717", "/articles/umeda-smoking-cafe", "suelog.jp", 120),
            row("20260717", "/lp", "www.suelog.jp", 20),
            row("20260717", "/lp", "aicoo.onrender.com", 999)
          ]
        }
      end

      private

      def self.row(date, path, host, views, page_location: nil)
        {
          "dimensionValues" => [
            { "value" => date },
            { "value" => path },
            { "value" => host },
            { "value" => page_location.to_s }
          ],
          "metricValues" => metric_values(views)
        }
      end

      def self.metric_values(views)
        [
          { "value" => views.to_s },
          { "value" => "10" },
          { "value" => "12" },
          { "value" => "3" },
          { "value" => "60" },
          { "value" => "0.5" },
          { "value" => "1" }
        ]
      end

      def row(date, path, host, views)
        self.class.row(date, path, host, views)
      end
    end
  end
end
