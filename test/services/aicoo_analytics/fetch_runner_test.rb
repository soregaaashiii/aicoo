require "test_helper"

module AicooAnalytics
  class FetchRunnerTest < ActiveSupport::TestCase
    test "creates success run for gsc fetch" do
      setting = AnalyticsSourceSetting.create!(source_type: "gsc", name: "Runner GSC", site_url: "sc-domain:suelog.jp")
      fake_fetcher = FakeSuccessFetcher.new(create_fetch_result("gsc"))

      with_fetcher_stub(GscFetcher, fake_fetcher) do
        assert_difference("AnalyticsFetchRun.where(status: 'success').count", 1) do
          run = FetchRunner.new(setting).call

          assert_equal "success", run.status
          assert_equal "gsc", run.source_type
          assert_equal 3, run.snapshot_count
          assert_equal 2, run.updated_neglect_loss_count
          assert run.finished_at.present?
        end
      end

      assert fake_fetcher.called
    end

    test "creates success run for ga4 fetch" do
      setting = AnalyticsSourceSetting.create!(source_type: "ga4", name: "Runner GA4", property_id: "123456789")
      fake_fetcher = FakeSuccessFetcher.new(create_fetch_result("ga4"))

      with_fetcher_stub(Ga4Fetcher, fake_fetcher) do
        run = FetchRunner.new(setting).call
        assert_equal "success", run.status
        assert_equal "ga4", run.source_type
      end

      assert fake_fetcher.called
    end

    test "creates failed run when fetcher raises" do
      setting = AnalyticsSourceSetting.create!(source_type: "gsc", name: "Runner failure", site_url: "sc-domain:suelog.jp")
      fake_fetcher = FakeFailureFetcher.new(GscSearchAnalyticsClient::Error.new("gsc failure"))

      with_fetcher_stub(GscFetcher, fake_fetcher) do
        assert_difference("AnalyticsFetchRun.where(status: 'failed').count", 1) do
          run = FetchRunner.new(setting).call

          assert_equal "failed", run.status
          assert_equal "gsc failure", run.error_message
          assert run.finished_at.present?
        end
      end

      assert fake_fetcher.called
    end

    test "records credential source summary when oauth refresh fails" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Runner OAuth failure",
        site_url: "sc-domain:suelog.jp",
        client_id: "saved-client",
        client_secret: "saved-secret",
        refresh_token: "saved-refresh-token"
      )
      fake_fetcher = FakeFailureFetcher.new(GoogleOauthClient::Error.new("Google OAuth error: 401 unauthorized_client"))

      with_fetcher_stub(GscFetcher, fake_fetcher) do
        run = FetchRunner.new(setting).call

        assert_equal "failed", run.status
        assert_includes run.error_message, "unauthorized_client"
        assert_includes run.error_message, "client_id_source=setting"
        assert_includes run.error_message, "client_secret_source=setting"
        assert_includes run.error_message, "refresh_token_source=setting"
        assert_includes run.error_message, "credentials_json_source=missing"
        assert_includes run.error_message, "oauth_connected_at=missing"
        refute_includes run.error_message, "saved-secret"
        refute_includes run.error_message, "saved-refresh-token"
      end
    end

    private

    def create_fetch_result(source_type)
      business = Business.create!(name: "Fetch runner #{source_type}")
      data_source = business.data_sources.create!(name: "#{source_type.upcase} source", source_type:)
      data_import = data_source.data_imports.create!(
        filename: "#{source_type}.csv",
        content_type: "text/csv",
        row_count: 1,
        raw_text: "metric,value\nsample,1\n",
        imported_at: Time.current
      )
      pipeline_result = ImportPipeline::Result.new(
        data_import_id: data_import.id,
        snapshot_count: 3,
        updated_neglect_loss_count: 2,
        skipped_count: 0
      )

      source_type == "gsc" ? GscFetcher::Result.new(data_import:, pipeline_result:) : Ga4Fetcher::Result.new(data_import:, pipeline_result:)
    end

    def with_fetcher_stub(fetcher_class, fake_fetcher)
      original_new = fetcher_class.method(:new)
      fetcher_class.define_singleton_method(:new) { |_setting| fake_fetcher }
      yield
    ensure
      fetcher_class.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    class FakeSuccessFetcher
      attr_reader :called

      def initialize(result)
        @result = result
        @called = false
      end

      def call
        @called = true
        @result
      end
    end

    class FakeFailureFetcher
      attr_reader :called

      def initialize(error)
        @error = error
        @called = false
      end

      def call
        @called = true
        raise @error
      end
    end
  end
end
