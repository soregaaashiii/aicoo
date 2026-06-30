module Admin
  class ActivityLearningE2eChecksController < ApplicationController
    def show
      @businesses = Business.real_businesses.order(:name)
      @business = selected_business
      @activity_learning_e2e_check = Aicoo::ActivityLearningE2eCheck.new(@business).call if @business
    end

    def repair
      business = Business.real_businesses.find(params[:business_id])
      Aicoo::ActivityLearningE2eCheck.repair!(business, params[:repair_action])
      redirect_to admin_activity_learning_e2e_check_path(business_id: business.id),
                  notice: "Activity Learningの安全な復旧を実行しました。"
    rescue StandardError => e
      redirect_to admin_activity_learning_e2e_check_path(business_id: params[:business_id]),
                  alert: "復旧に失敗しました: #{e.message}"
    end

    private

    def selected_business
      return Business.real_businesses.find_by(id: params[:business_id]) if params[:business_id].present?

      Business.real_businesses.order(:name).first
    end
  end
end
