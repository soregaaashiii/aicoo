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

    class CountingRunner
      attr_reader :call_count

      def initialize
        @call_count = 0
      end

      def call
        @call_count += 1
      end
    end
  end
end
