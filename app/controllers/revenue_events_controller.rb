class RevenueEventsController < ApplicationController
  before_action :set_revenue_event, only: %i[show edit update destroy]

  def index
    @revenue_events = RevenueEvent.includes(:business, :action_candidate, :action_result, :action_execution_log)
                                  .order(occurred_on: :desc, created_at: :desc)
  end

  def show
  end

  def new
    @revenue_event = RevenueEvent.new(
      occurred_on: Date.current,
      event_type: "revenue",
      business_id: revenue_event_prefill_params[:business_id],
      action_candidate_id: revenue_event_prefill_params[:action_candidate_id],
      action_result_id: revenue_event_prefill_params[:action_result_id],
      action_execution_log_id: revenue_event_prefill_params[:action_execution_log_id]
    )
    prefill_learning_loop_links(@revenue_event)
  end

  def edit
  end

  def create
    @revenue_event = RevenueEvent.new(revenue_event_params)

    if @revenue_event.save
      redirect_to revenue_events_path, notice: "収益記録を作成しました。"
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @revenue_event.update(revenue_event_params)
      redirect_to revenue_events_path, notice: "収益記録を更新しました。", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @revenue_event.destroy!

    redirect_to revenue_events_path, notice: "収益記録を削除しました。", status: :see_other
  end

  private

  def set_revenue_event
    @revenue_event = RevenueEvent.find(params.expect(:id))
  end

  def revenue_event_params
    params.expect(
      revenue_event: %i[
        business_id
        occurred_on
        amount
        event_type
        action_candidate_id
        action_result_id
        action_execution_log_id
      ]
    )
  end

  def revenue_event_prefill_params
    params.fetch(:revenue_event, ActionController::Parameters.new)
          .permit(:business_id, :action_candidate_id, :action_result_id, :action_execution_log_id)
  end

  def prefill_learning_loop_links(revenue_event)
    if revenue_event.action_result
      revenue_event.action_candidate ||= revenue_event.action_result.action_candidate
      revenue_event.action_execution_log ||= revenue_event.action_result.action_execution_logs.recent.first
    end
    if revenue_event.action_execution_log
      revenue_event.action_candidate ||= revenue_event.action_execution_log.action_candidate
      revenue_event.action_result ||= revenue_event.action_execution_log.action_result
    end
    revenue_event.business ||= revenue_event.action_candidate&.business ||
                               revenue_event.action_result&.business ||
                               revenue_event.action_execution_log&.business
  end
end
