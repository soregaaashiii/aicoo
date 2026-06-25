require "test_helper"

module Aicoo
  class BusinessPlaybookSummaryTest < ActiveSupport::TestCase
    test "summarizes learned and low confidence businesses" do
      BusinessPlaybook.create!(
        business: businesses(:suelog),
        sample_count: 15,
        confidence_score: 60,
        top_action_type: "seo_improvement"
      )

      summary = BusinessPlaybookSummary.new.call

      assert_equal Business.count, summary.total_businesses
      assert_equal 1, summary.learned_businesses_count
      assert_operator summary.average_confidence, :>, 0
      assert_includes summary.top_playbooks.map(&:business), businesses(:suelog)
    end
  end
end
