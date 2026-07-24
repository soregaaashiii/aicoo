module Owner
  class FocusController < ApplicationController
    def show
      Aicoo::MemoryDiagnostics.measure("Owner::FocusController#show", context: memory_diagnostics_context) do
        @today_board = Aicoo::MemoryDiagnostics.measure("Owner::FocusController#show.today_board", context: memory_diagnostics_context(mode: params[:mode])) do
          Aicoo::TodayActionBoard.new(
            mode: params[:mode],
            page: params[:today_actions_page],
            page_param: :today_actions_page
          ).call
        end
      end
    end

    def defer
      key = params[:task_key].to_s
      session[:ceo_deferred_task_keys] = (deferred_task_keys + [ key ]).uniq if key.present?
      redirect_to owner_focus_path, notice: "後でやるに移しました。"
    end

    def restore
      key = params[:task_key].to_s
      session[:ceo_deferred_task_keys] = deferred_task_keys - [ key ] if key.present?
      redirect_to owner_focus_path, notice: "今日のランキングに戻しました。"
    end

    private

    def deferred_task_keys
      Array(session[:ceo_deferred_task_keys]).compact_blank
    end
  end
end
