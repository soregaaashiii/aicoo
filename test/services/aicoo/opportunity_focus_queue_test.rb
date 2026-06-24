require "test_helper"

module Aicoo
  class OpportunityFocusQueueTest < ActiveSupport::TestCase
    setup do
      OpportunityDiscoveryItem.delete_all
      ActionResult.delete_all
      ActionExecution.delete_all
    end

    test "calculates focus score and selects top item" do
      create_source_result(source_type: "owner_discovery", actual: 10_000)
      create_source_result(source_type: "owner_discovery", actual: 12_000)
      weak = OpportunityDiscoveryItem.create!(
        title: "Weak source opportunity",
        source_type: "trend",
        business: businesses(:suelog),
        opportunity_score: 60
      )
      strong = OpportunityDiscoveryItem.create!(
        title: "Strong source opportunity",
        source_type: "owner_discovery",
        business: businesses(:suelog),
        opportunity_score: 60
      )

      queue = OpportunityFocusQueue.new.call

      assert_equal 2, queue.total_count
      assert_equal strong, queue.top_item.opportunity
      assert_equal "high", queue.top_item.priority
      assert_operator queue.top_item.focus_score, :>, 80
      assert_includes queue.top_item.reason, "発見源補正"
      assert queue.items.any? { |item| item.opportunity == weak }
    end

    test "stale opportunity receives penalty" do
      stale = OpportunityDiscoveryItem.create!(
        title: "Stale opportunity",
        source_type: "owner_discovery",
        business: businesses(:suelog),
        opportunity_score: 50,
        discovered_at: 31.days.ago
      )

      item = OpportunityFocusQueue.new.call.items.find { |queue_item| queue_item.opportunity == stale }

      assert_includes item.reason, "未レビュー経過: -10"
    end

    private

    def create_source_result(source_type:, actual:)
      opportunity = OpportunityDiscoveryItem.create!(
        title: "#{source_type} focus history #{SecureRandom.hex(4)}",
        source_type:,
        business: businesses(:suelog)
      )
      candidate = opportunity.convert_to_action_candidate!
      candidate.create_action_execution!(status: "completed", execution_type: "manual", completed_at: Time.current)
      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        predicted_expected_profit_yen: 10_000,
        predicted_success_probability: 0.8,
        actual_profit_yen: actual,
        actual_revenue_yen: actual
      )
    end
  end
end
