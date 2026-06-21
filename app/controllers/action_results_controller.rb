class ActionResultsController < ApplicationController
  before_action :set_action_result, only: %i[show edit update evaluate]

  def index
    @action_results = ActionResult.includes(:business, :action_candidate).order(created_at: :desc)
  end

  def show
  end

  def new
    action_candidate = ActionCandidate.find(params.dig(:action_result, :action_candidate_id) || params[:action_candidate_id])
    @action_result = ActionResult.new(
      action_candidate:,
      business: action_candidate.business,
      executed_on: Date.current,
      evaluated_on: Date.current
    )
  end

  def create
    @action_result = ActionResult.new(action_result_params)

    if @action_result.save
      redirect_to @action_result, notice: "Action result was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
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
        :note
      ]
    )
  end
end
