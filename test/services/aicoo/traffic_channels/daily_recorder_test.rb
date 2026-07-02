require "test_helper"

module Aicoo
  module TrafficChannels
    class DailyRecorderTest < ActiveSupport::TestCase
      test "records serp analyses as traffic channel runs" do
        business = businesses(:suelog)
        run = AicooDailyRun.create!(target_date: Date.current, status: "success", finished_at: Time.current)
        business.serp_analyses.create!(
          keyword: "梅田 喫煙",
          analyzed_at: Date.current.noon,
          search_engine: "google",
          device: "desktop",
          provider: "serper",
          status: "success",
          result_count: 8
        )

        result = DailyRecorder.record!(daily_run: run)

        assert_equal 1, result.recorded_count
        traffic_run = TrafficChannelRun.find_by!(business:, channel_key: "serp")
        assert_equal "success", traffic_run.status
        assert_equal 8, traffic_run.clicks
        assert_equal run.id, traffic_run.metadata["aicoo_daily_run_id"]
      end
    end
  end
end
