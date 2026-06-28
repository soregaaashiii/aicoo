module Admin
  class ExecutionRunsController < ApplicationController
    def index
      @operation_monitor = Aicoo::LongRunningOperationMonitor.new.call
      @operations = (@operation_monitor.running_operations + @operation_monitor.recent_operations)
    end

    def show
      @operation_monitor = Aicoo::LongRunningOperationMonitor.new.call
      @operation = (@operation_monitor.running_operations + @operation_monitor.recent_operations)
        .find { |operation| operation.key == params[:id].to_s }

      return if @operation

      redirect_to admin_execution_runs_path, alert: "指定された実行履歴が見つかりません。"
    end
  end
end
