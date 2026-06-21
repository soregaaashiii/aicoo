class RevenueEventsController < ApplicationController
  before_action :set_revenue_event, only: %i[show edit update destroy]

  def index
    @revenue_events = RevenueEvent.includes(:business).order(occurred_on: :desc, created_at: :desc)
  end

  def show
  end

  def new
    @revenue_event = RevenueEvent.new(
      occurred_on: Date.current,
      event_type: "revenue",
      business_id: params.dig(:revenue_event, :business_id)
    )
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
    params.expect(revenue_event: %i[business_id occurred_on amount event_type])
  end
end
