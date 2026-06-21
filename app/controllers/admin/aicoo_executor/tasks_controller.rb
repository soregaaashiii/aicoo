module Admin
  module AicooExecutor
    class TasksController < ApplicationController
      def index
        @tasks = filtered_tasks
        @summary = Summary.new
      end

      def show
        @task = task
      end

      def create
        revenue_execution = AicooRevenueExecution.find(task_params.fetch(:aicoo_revenue_execution_id))
        task = ::AicooExecutor::TaskBuilder.from_revenue_execution(revenue_execution)

        redirect_to admin_aicoo_executor_task_path(task), notice: "Executor task created."
      end

      def approve
        task.approve!

        redirect_to admin_aicoo_executor_task_path(task), notice: "Executor task approved."
      end

      def reject
        task.reject!

        redirect_to admin_aicoo_executor_task_path(task), notice: "Executor task rejected."
      end

      def done
        task.complete!

        redirect_to admin_aicoo_executor_task_path(task), notice: "Executor task completed."
      end

      private

      def task
        @task ||= ::AicooExecutorTask.find(params.expect(:id))
      end

      def task_params
        params.expect(aicoo_executor_task: [ :aicoo_revenue_execution_id ])
      end

      def filtered_tasks
        tasks = ::AicooExecutorTask.recent
        tasks = tasks.where(execution_type: params[:execution_type]) if params[:execution_type].present?
        tasks
      end

      Summary = Data.define do
        def waiting_count
          ::AicooExecutorTask.waiting_execution.count
        end

        def approval_pending_count
          ::AicooExecutorTask.approval_pending.count
        end

        def done_count
          ::AicooExecutorTask.done.count
        end

        def data_preparation_count
          ::AicooExecutorTask.data_preparation.count
        end
      end
    end
  end
end
