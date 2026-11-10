require "test_helper"

module AicooAnalytics
  class DailyFetchJobTest < ActiveJob::TestCase
    test "fetches enabled settings and skips disabled settings" do
      AnalyticsSourceSetting.create!(source_type: "gsc", name: "Daily GSC", site_url: "sc-domain:suelog.jp")
      AnalyticsSourceSetting.create!(source_type: "ga4", name: "Daily GA4", property_id: "123456789")
      AnalyticsSourceSetting.create!(source_type: "gsc", name: "Daily disabled", site_url: "sc-domain:disabled.jp", enabled: false)
      fake_runner = CountingRunner.new

      with_runner_stub(fake_runner) do
        DailyFetchJob.perform_now
      end

      assert_equal 2, fake_runner.call_count
    end

    test "refreshes all linked business metric days once after source fetches" do
      AnalyticsSourceSetting.update_all(enabled: false)
      business = Business.create!(name: "Daily metric owner")
      site = AicooAnalyticsSite.create!(name: "Daily metric site", domain: "daily.example", business:)
      AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Daily metric GSC",
        site_url: "sc-domain:daily.example",
        fetch_days: 28,
        aicoo_analytics_site: site
      )
      AnalyticsSourceSetting.create!(
        source_type: "ga4",
        name: "Daily metric GA4",
        property_id: "987654321",
        fetch_days: 14,
        aicoo_analytics_site: site
      )
      fake_runner = SuccessfulRunner.new
      importer_calls = []

      with_runner_stub(fake_runner) do
        with_metric_importer_stub(importer_calls) { DailyFetchJob.perform_now }
      end

      assert_equal 2, fake_runner.call_count
      assert_equal 1, importer_calls.size
      assert_equal business, importer_calls.first.fetch(:business)
      assert_equal 28, importer_calls.first.fetch(:days)
      assert_equal %w[ga4 gsc], importer_calls.first.fetch(:source_types).sort
    end

    private

    def with_runner_stub(fake_runner)
      original_new = FetchRunner.method(:new)
      FetchRunner.define_singleton_method(:new) { |_setting| fake_runner }
      yield
    ensure
      FetchRunner.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    def with_metric_importer_stub(calls)
      original_new = BusinessGoogleApiMetricImporter.method(:new)
      BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |**attributes|
        calls << attributes
        Object.new.tap { |object| object.define_singleton_method(:call) { true } }
      end
      yield
    ensure
      BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    class CountingRunner
      attr_reader :call_count

      def initialize
        @call_count = 0
      end

      def call
        @call_count += 1
      end
    end

    class SuccessfulRunner < CountingRunner
      def call
        super
        Struct.new(:status).new("success")
      end
    end
  end
end
