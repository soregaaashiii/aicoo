require "test_helper"

module Aicoo
  class OwnerExecutionQueueSummaryTest < ActiveSupport::TestCase
    test "loads queue rows and status counts without duplicate queries" do
      create_queue_item(item_id: 91_001, status: "pending", priority_score: 20)
      top_item = create_queue_item(item_id: 91_002, status: "pending", priority_score: 40)
      skipped_item = create_queue_item(item_id: 91_003, status: "skipped", priority_score: 10)
      create_queue_item(item_id: 91_004, status: "completed", priority_score: 30)

      query_count, summary = count_queue_queries do
        OwnerExecutionQueueSummary.new(due_on: Date.current).call
      end

      assert_equal [ 91_002, 91_001 ], summary.items.map(&:item_id)
      assert_equal [ skipped_item.id ], summary.skipped_items.map(&:id)
      assert_equal 2, summary.pending_count
      assert_equal 1, summary.completed_count
      assert_equal 1, summary.skipped_count
      assert_equal top_item.id, summary.top_item.id
      assert_operator query_count, :<=, 3
    end

    private

    def create_queue_item(item_id:, status:, priority_score:)
      OwnerExecutionQueueItem.create!(
        item_type: "action_candidate",
        item_id:,
        title: "Queue item #{item_id}",
        due_on: Date.current,
        status:,
        priority_score:
      )
    end

    def count_queue_queries
      count = 0
      subscriber = lambda do |_name, _started, _finished, _id, payload|
        next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION]) || payload[:cached]
        next unless payload[:sql].to_s.match?(/\ASELECT/i)

        count += 1 if payload[:sql].include?('"owner_execution_queue_items"')
      end

      result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      [ count, result ]
    end
  end
end
