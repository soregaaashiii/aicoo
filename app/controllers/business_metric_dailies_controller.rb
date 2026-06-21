class BusinessMetricDailiesController < ApplicationController
  before_action :set_business_metric_daily, only: %i[show edit update destroy]

  def index
    @business_metric_dailies = BusinessMetricDaily.includes(:business).order(recorded_on: :desc, created_at: :desc)
  end

  def show
  end

  def new
    @business_metric_daily = BusinessMetricDaily.new(
      recorded_on: Date.current,
      business_id: params.dig(:business_metric_daily, :business_id)
    )
  end

  def edit
  end

  def create
    @business_metric_daily = BusinessMetricDaily.new(business_metric_daily_params)

    if @business_metric_daily.save
      redirect_to business_metric_dailies_path, notice: "代理指標を作成しました。"
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @business_metric_daily.update(business_metric_daily_params)
      redirect_to business_metric_dailies_path, notice: "代理指標を更新しました。", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @business_metric_daily.destroy!

    redirect_to business_metric_dailies_path, notice: "代理指標を削除しました。", status: :see_other
  end

  private

  def set_business_metric_daily
    @business_metric_daily = BusinessMetricDaily.find(params.expect(:id))
  end

  def business_metric_daily_params
    params.expect(
      business_metric_daily: %i[
        business_id
        recorded_on
        impressions
        clicks
        sessions
        pageviews
        phone_clicks
        map_clicks
        affiliate_clicks
      ]
    )
  end
end
