module Admin
  class BusinessActivityLogsController < ApplicationController
    ListRow = Data.define(
      :id,
      :business_id,
      :activity_type,
      :resource_type,
      :resource_id,
      :title,
      :occurred_at,
      :diff_summary,
      :source_method,
      :evaluation_status,
      :business_name
    )
    LIST_COLUMNS = [
      "business_activity_logs.id",
      "business_activity_logs.business_id",
      "business_activity_logs.activity_type",
      "business_activity_logs.resource_type",
      "business_activity_logs.resource_id",
      "business_activity_logs.title",
      "business_activity_logs.occurred_at",
      "business_activity_logs.diff_summary",
      "business_activity_logs.source_method",
      "business_activity_logs.evaluation_status",
      "businesses.name"
    ].map { |column| Arel.sql(column) }.freeze

    def index
      @businesses = Business.real_businesses.select(:id, :name).order(:name)
      scope = BusinessActivityLog.joins(:business).recent
      @business_activity_logs = filter_scope(scope)
        .limit(200)
        .pluck(*LIST_COLUMNS)
        .map { |attributes| ListRow.new(*attributes) }
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
