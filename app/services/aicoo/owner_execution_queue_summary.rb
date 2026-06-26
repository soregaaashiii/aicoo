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
      Result.new(
        items: items.to_a,
        skipped_items: skipped_items.to_a,
        pending_count: scope.pending.count,
        completed_count: scope.completed.count,
        skipped_count: scope.skipped.count,
        top_item: items.first,
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
