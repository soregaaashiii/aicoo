module Admin
  module AicooRevenue
    class ExecutionsController < ApplicationController
      def index
        @status = params[:status]
        @summary_executions = ::AicooRevenueExecution.all
        @executions = filtered_executions.recent
      end

      def show
        @execution = execution
      end

      def create
        execution = ::AicooRevenue::ExecutionPlanner.new(**execution_params.to_h.symbolize_keys).call

        redirect_to admin_aicoo_revenue_executions_path, notice: "Revenue action planned: #{execution.title}"
      rescue ActiveRecord::RecordNotFound => e
        redirect_to admin_aicoo_revenue_path, alert: e.message
      end

      def edit
        @execution = execution
        @datahub_snapshot = latest_datahub_snapshot
        preset_actual_profit_from_snapshot
      end

      def update
        if execution.update(result_params)
          redirect_to admin_aicoo_revenue_executions_path, notice: "Revenue result saved."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def done
        execution.mark_done!

        redirect_to admin_aicoo_revenue_executions_path, notice: "Revenue action marked done."
      end

      def skipped
        execution.mark_skipped!(note: params.dig(:aicoo_revenue_execution, :note))

        redirect_to admin_aicoo_revenue_executions_path, notice: "Revenue action skipped."
      end

      def sync_action_candidate_done
        action_candidate = execution.source_action_candidate

        if execution.status == "done" && action_candidate
          action_candidate.update!(status: "done")
          redirect_to admin_aicoo_revenue_execution_path(execution), notice: "ActionCandidate marked done."
        else
          redirect_to admin_aicoo_revenue_execution_path(execution), alert: "This Revenue execution cannot sync an ActionCandidate."
        end
      end

      private

      def execution
        @execution ||= ::AicooRevenueExecution.find(params.expect(:id))
      end

      def execution_params
        params.expect(
          aicoo_revenue_execution: %i[
            source_type source_id available_minutes available_budget_yen source
          ]
        )
      end

      def result_params
        params.expect(aicoo_revenue_execution: %i[actual_90d_profit_yen result_note])
      end

      def filtered_executions
        case @status
        when "planned"
          ::AicooRevenueExecution.planned
        when "done"
          ::AicooRevenueExecution.done
        when "skipped"
          ::AicooRevenueExecution.where(status: "skipped")
        when "scored"
          ::AicooRevenueExecution.scored
        else
          ::AicooRevenueExecution.all
        end
      end

      def latest_datahub_snapshot
        AicooDataSnapshot.where(source_type: "revenue_execution", source_id: execution.id).recent.first
      end

      def preset_actual_profit_from_snapshot
        return unless @datahub_snapshot
        return if @execution.actual_90d_profit_yen.present?

        snapshot_value = @datahub_snapshot.payload["actual_90d_profit_yen"]
        @execution.actual_90d_profit_yen = snapshot_value if snapshot_value.present?
      end
    end
  end
end
