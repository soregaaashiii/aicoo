class ActionExecutionLogsController < ApplicationController
  before_action :set_action_execution_log, only: %i[show edit update]

  def show
  end

  def new
    action_candidate = ActionCandidate.find(params[:action_candidate_id])
    @action_execution_log = ActionExecutionLog.new(
      action_candidate:,
      business: action_candidate.business,
      planned_action: planned_action_for(action_candidate),
      planned_quantity: planned_quantity_for(action_candidate),
      started_at: Time.current,
      finished_at: Time.current
    )
  end

  def create
    @action_execution_log = ActionExecutionLog.new(action_execution_log_params)

    if @action_execution_log.save
      redirect_to @action_execution_log, notice: "実行差分を記録しました。"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @action_execution_log.update(action_execution_log_params)
      redirect_to @action_execution_log, notice: "実行差分を更新しました。"
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_action_execution_log
    @action_execution_log = ActionExecutionLog.find(params.expect(:id))
  end

  def action_execution_log_params
    params.expect(
      action_execution_log: [
        :action_candidate_id,
        :business_id,
        :user_id,
        :action_result_id,
        :revenue_event_id,
        :planned_action,
        :planned_quantity,
        :actual_action,
        :actual_quantity,
        :variance_reason,
        :human_note,
        :status,
        :started_at,
        :finished_at
      ]
    )
  end

  def planned_action_for(action_candidate)
    [
      action_candidate.title,
      action_candidate.execution_prompt.presence || action_candidate.description
    ].compact.join("\n")
  end

  def planned_quantity_for(action_candidate)
    planned_action_for(action_candidate)[/(\d+(?:\.\d+)?)\s*(?:件|本|記事|店舗|個|回)/, 1]
  end
end
