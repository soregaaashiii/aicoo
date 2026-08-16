module Aicoo
  class OwnerExecutionQueueSummary
    Result = Data.define(
      :items,
      :skipped_items,
      :pending_count,
      :completed_count,
      :skipped_count,
      :top_item,
      :generated_at
    )

    def initialize(due_on: Date.current)
      @due_on = due_on.to_date
    end

    def call
      pending_items = items.to_a
      skipped_queue_items = skipped_items.to_a
      counts_by_status = scope.group(:status).count

      Result.new(
        items: pending_items,
        skipped_items: skipped_queue_items,
        pending_count: counts_by_status.fetch("pending", 0),
        completed_count: counts_by_status.fetch("completed", 0),
        skipped_count: counts_by_status.fetch("skipped", 0),
        top_item: pending_items.first,
        generated_at: Time.current
      )
    end

    private

    attr_reader :due_on

    def scope
      OwnerExecutionQueueItem.where(due_on:)
    end

    def items
      scope.pending.ordered.limit(10)
    end

    def skipped_items
      scope.skipped.ordered.limit(10)
    end
  end
end
