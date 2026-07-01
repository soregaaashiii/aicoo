module Admin
  class AicooResourceBudgetsController < ApplicationController
    def show
      @budget = AicooResourceBudget.current
      @summary = Aicoo::ResourceAwareAutoBuildSummary.new.call
    end

    def update
      @budget = AicooResourceBudget.current
      if @budget.update(budget_params)
        redirect_to admin_aicoo_resource_budget_path, notice: "AICOO Resource Budgetを保存しました。"
      else
        @summary = Aicoo::ResourceAwareAutoBuildSummary.new.call
        render :show, status: :unprocessable_entity
      end
    end

    private

    def budget_params
      params.require(:aicoo_resource_budget).permit(
        :codex_concurrent_limit,
        :codex_waiting_limit,
        :build_queue_limit,
        :deploy_queue_limit,
        :render_service_limit,
        :monthly_ai_budget_yen,
        :current_month_ai_spend_yen,
        :simultaneous_mvp_limit,
        :auto_build_enabled
      )
    end
  end
end
