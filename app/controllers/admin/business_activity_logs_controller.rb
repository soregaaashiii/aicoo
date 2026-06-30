module Admin
  class BusinessActivityLogsController < ApplicationController
    def index
      @businesses = Business.real_businesses.order(:name)
      @business_activity_logs = BusinessActivityLog.includes(:business)
                                                  .recent
                                                  .then { |scope| filter_scope(scope) }
                                                  .limit(200)
    end

    def show
      @business_activity_log = BusinessActivityLog.includes(:business, :activity_evaluations).find(params[:id])
    end

    private

    def filter_scope(scope)
      scope = scope.where(business_id: params[:business_id]) if params[:business_id].present?
      scope = scope.where(activity_type: params[:activity_type]) if params[:activity_type].present?
      scope = scope.where(evaluation_status: params[:evaluation_status]) if params[:evaluation_status].present?
      scope
    end
  end
end
