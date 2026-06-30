class BusinessServicesController < ApplicationController
  before_action :set_business
  before_action :set_business_service, only: %i[update]

  def create
    @business_service = @business.business_services.new(business_service_params)
    if @business_service.save
      redirect_to business_path(@business, anchor: "business-services"), notice: "Serviceを登録しました。"
    else
      redirect_to business_path(@business, anchor: "business-services"),
                  alert: "Serviceを登録できませんでした: #{@business_service.errors.full_messages.to_sentence}"
    end
  end

  def update
    if @business_service.update(business_service_params)
      redirect_to business_path(@business, anchor: "business-services"), notice: "Serviceを保存しました。"
    else
      redirect_to business_path(@business, anchor: "business-services"),
                  alert: "Serviceを保存できませんでした: #{@business_service.errors.full_messages.to_sentence}"
    end
  end

  private

  def set_business
    @business = Business.real_businesses.find(params[:business_id])
  end

  def set_business_service
    @business_service = @business.business_services.find(params[:id])
  end

  def business_service_params
    params.require(:business_service).permit(
      :name,
      :url,
      :repository,
      :deploy_target,
      :render_service,
      :stripe_account,
      :domain,
      :api_endpoint,
      :status
    )
  end
end
