module Owner
  class ExecutionQueueItemsController < ApplicationController
    before_action :set_owner_execution_queue_item

    def complete
      previous_status = @owner_execution_queue_item.status
      @owner_execution_queue_item.complete!
      record_decision!("complete", previous_status:)
      redirect_back fallback_location: owner_tasks_path, notice: "Queue Itemをcompletedにしました。"
    end

    def skip
      previous_status = @owner_execution_queue_item.status
      @owner_execution_queue_item.skip!
      record_decision!("skip", previous_status:)
      redirect_back fallback_location: owner_tasks_path, notice: "Queue Itemをskippedにしました。"
    end

    def restore
      previous_status = @owner_execution_queue_item.status
      @owner_execution_queue_item.restore!
      record_decision!("restore", previous_status:)
      redirect_back fallback_location: owner_focus_path, notice: "今日のキューに戻しました。"
    end

    private

    def set_owner_execution_queue_item
      @owner_execution_queue_item = OwnerExecutionQueueItem.find(params.expect(:id))
    end

    def record_decision!(decision_type, previous_status:)
      OwnerDecisionLog.record!(
        subject: @owner_execution_queue_item,
        queue_item: @owner_execution_queue_item,
        decision_type:,
        decision_source: "owner_tasks",
        previous_status:,
        new_status: @owner_execution_queue_item.status
      )
    end
  end
end
