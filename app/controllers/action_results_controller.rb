class ActionResultsController < ApplicationController
  before_action :set_action_result, only: %i[show edit update evaluate]

  def index
    @action_results = ActionResult.includes(:business, :action_candidate).order(created_at: :desc)
  end

  def show
  end

  def new
    if params[:action_execution_id].present? || params.dig(:action_result, :action_execution_id).present?
      action_execution = ActionExecution.find(params[:action_execution_id] || params.dig(:action_result, :action_execution_id))
      if action_execution.action_result
        redirect_to action_execution.action_result, notice: "このActionExecutionの結果は登録済みです。"
      else
        @action_result = Aicoo::ActionResultDraftBuilder.new(action_execution).call
      end
      return
    end

    action_candidate = ActionCandidate.find(params.dig(:action_result, :action_candidate_id) || params[:action_candidate_id])
    @action_result = ActionResult.new(action_candidate:, business: action_candidate.business, executed_on: Date.current, evaluated_on: Date.current)
  end

  def create
    @action_result = ActionResult.new(action_result_params)
    apply_action_expansion_learning

    if @action_result.save
      redirect_to @action_result, notice: "Action result was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    apply_action_expansion_learning
    if @action_result.update(action_result_params)
      redirect_to @action_result, notice: "Action result was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def evaluate
    ActionResultEvaluator.new(@action_result).call
    redirect_to @action_result, notice: "Action result was evaluated."
  end

  private

  def set_action_result
    @action_result = ActionResult.find(params.expect(:id))
  end

  def action_result_params
    params.expect(
      action_result: [
        :action_candidate_id,
        :action_execution_id,
        :business_id,
        :executed_on,
        :evaluated_on,
        :actual_revenue_yen,
        :actual_profit_yen,
        :actual_proxy_score_delta,
        :actual_impressions_delta,
        :actual_clicks_delta,
        :actual_sessions_delta,
        :actual_pageviews_delta,
        :actual_phone_clicks_delta,
        :actual_map_clicks_delta,
        :actual_affiliate_clicks_delta,
        :evaluation_status,
        :note,
        metadata: {}
      ]
    )
  end

  def apply_action_expansion_learning
    result = defined?(@action_result) ? @action_result : nil
    return unless result

    candidate = result.action_candidate || ActionCandidate.find_by(id: action_result_params[:action_candidate_id])
    expansion = candidate&.metadata.to_h["action_expansion"].to_h
    tasks = Array(expansion["recommended_tasks"])
    return if tasks.empty?

    executed_tasks = Array(params[:executed_expansion_tasks]).compact_blank
    result.metadata = result.metadata.to_h.merge(
      "action_expansion_learning" => {
        "version" => expansion["version"],
        "expansion_type" => expansion["expansion_type"],
        "available_tasks" => tasks,
        "executed_tasks" => executed_tasks,
        "skipped_tasks" => tasks - executed_tasks,
        "task_priority" => expansion["task_priority"].to_h,
        "confidence" => expansion["confidence"].to_s,
        "captured_at" => Time.current.iso8601
      }
    )
  end
end
