require "test_helper"

module Aicoo
  class SystemStatusResolverTest < ActiveSupport::TestCase
    test "returns four-level status for business google sources" do
      business = businesses(:suelog)

      status = SystemStatusResolver.call("ga4", business:)

      assert_includes SystemStatusResolver::STATUSES, status.status
      assert_equal "GA4", status.label
      assert status.reason.present?
      assert status.detail_url.present?
    end

    test "returns daily run status from shared execution resolver" do
      status = SystemStatusResolver.call("daily_run")

      assert_includes SystemStatusResolver::STATUSES, status.status
      assert_equal "Daily Run", status.label
      assert status.reason.present?
    end

    test "returns traffic serp status from serp run summary" do
      status = SystemStatusResolver.call("traffic_serp")

      assert_includes SystemStatusResolver::STATUSES, status.status
      assert_equal "SERP", status.label
      assert_match(/今日/, status.reason)
      assert_equal "SerpRun", status.source
    end
  end
end
