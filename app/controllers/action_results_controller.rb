class ActionResultsController < ApplicationController
  before_action :set_action_result, only: %i[show edit update evaluate]

  MANUAL_ACTUAL_FIELDS = ActionResult::MANUAL_ACTUAL_FIELDS

  def index
    @action_results = ActionResult.includes(:business, :action_candidate).order(created_at: :desc)
  end

  def show
  end

  def new
    @return_to = safe_return_to

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
    @action_result = ActionResult.new(action_result_attributes(source: "action_result_create"))
    apply_action_expansion_learning

    if @action_result.save
      evaluate_or_refresh_action_result(@action_result, source: "action_result_create")
      redirect_to safe_return_to || @action_result, notice: "Action result was successfully created."
    else
      @return_to = safe_return_to
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    apply_action_expansion_learning
    if @action_result.update(action_result_attributes(source: "action_result_update"))
      evaluate_or_refresh_action_result(@action_result, source: "action_result_update")
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

  def action_result_attributes(source:)
    attrs = action_result_params.to_h
    return attrs unless manual_actual_param_present?

    attrs["evaluation_status"] = "pending" unless attrs["evaluation_status"].to_s == "evaluated"
    attrs["metadata"] = attrs.fetch("metadata", {}).to_h.merge(manual_actual_metadata(source:))
    attrs
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

  def safe_return_to
    return_to = params[:return_to].to_s
    return if return_to.blank?
    return unless return_to.start_with?("/")
    return if return_to.start_with?("//")

    return_to
  end

  def evaluate_or_refresh_action_result(action_result, source:)
    if action_result.evaluation_status == "pending" && action_result.evaluated_on <= Date.current
      ActionResultEvaluator.new(action_result).call
    else
      Aicoo::ExpectedValueLearningRefresh.refresh_after_action_result!(action_result, source:)
    end
  rescue StandardError => e
    Rails.logger.warn("[ExpectedValueLearning] evaluation/refresh failed action_result_id=#{action_result.id} source=#{source} error=#{e.class}: #{e.message}")
  end

  def manual_actual_metadata(source:)
    {
      "manual_actuals_recorded" => true,
      "manual_actuals_recorded_source" => source,
      "manual_actuals_recorded_at" => Time.current.iso8601
    }
  end

  def manual_actual_param_present?
    raw_params = params[:action_result]
    return false unless raw_params.respond_to?(:key?)

    MANUAL_ACTUAL_FIELDS.any? { |field| actual_param_value_present?(raw_params, field) } ||
      manual_actual_metadata_values(raw_params).any? { |_key, value| value.present? }
  end

  def actual_param_value_present?(raw_params, field)
    value = raw_params[field] || raw_params[field.to_s]
    value.present?
  end

  def manual_actual_metadata_values(raw_params)
    values = raw_params.dig(:metadata, :manual_actuals) || raw_params.dig("metadata", "manual_actuals")
    values.respond_to?(:to_h) ? values.to_h : {}
  end
end
