require "test_helper"

module Owner
  class ExecutionQueueItemsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @item = OwnerExecutionQueueItem.create!(
        item_type: "opportunity",
        item_id: 1,
        title: "Queue item",
        risk_level: "low",
        status: "pending",
        due_on: Date.current
      )
    end

    test "marks item completed" do
      assert_difference("OwnerDecisionLog.count", 1) do
        patch complete_owner_execution_queue_item_url(@item)
      end

      assert_redirected_to owner_tasks_url
      assert_equal "completed", @item.reload.status
      assert_equal "complete", OwnerDecisionLog.last.decision_type
      assert_equal @item, OwnerDecisionLog.last.queue_item
    end

    test "marks item skipped" do
      assert_difference("OwnerDecisionLog.count", 1) do
        patch skip_owner_execution_queue_item_url(@item)
      end

      assert_redirected_to owner_tasks_url
      assert_equal "skipped", @item.reload.status
      assert_equal "skip", OwnerDecisionLog.last.decision_type
    end
  end
end
