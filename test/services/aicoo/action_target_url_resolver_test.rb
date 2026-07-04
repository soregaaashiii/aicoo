require "test_helper"

module Aicoo
  class ActionTargetUrlResolverTest < ActiveSupport::TestCase
    test "rejects metric-derived pseudo paths" do
      assert_nil ActionTargetUrlResolver.call("/map/affiliate_clicks")
      assert_nil ActionTargetUrlResolver.call("phone_clicks")
      assert ActionTargetUrlResolver.metric_reference?("/map/affiliate_clicks")
    end

    test "allows existing rails route paths" do
      assert_equal "/businesses", ActionTargetUrlResolver.call("/businesses")
      assert_equal "/businesses/1", ActionTargetUrlResolver.call("/businesses/1")
    end

    test "rejects unknown paths when route validation is required" do
      assert_nil ActionTargetUrlResolver.call("/not_a_real_action_candidate_target")
    end
  end
end
