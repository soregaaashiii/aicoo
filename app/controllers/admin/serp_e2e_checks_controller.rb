module Admin
  class SerpE2eChecksController < ApplicationController
    def show
      load_context
      @serp_e2e_check = Aicoo::Serp::E2eCheck.new(@business).call if @business
    end

    def repair
      business = Business.real_businesses.find(params.expect(:business_id))
      result = Aicoo::Serp::E2eCheck.repair!(
        business:,
        action: params.expect(:repair_action)
      )
      redirect_to admin_serp_e2e_check_path(business_id: business.id),
                  notice: "SERP E2E復旧を実行しました。現在の状態: #{result.health_label}"
    rescue StandardError => e
      redirect_to admin_serp_e2e_check_path(business_id: params[:business_id]),
                  alert: "SERP E2E復旧に失敗しました: #{e.message}"
    end

    private

    def load_context
      @businesses = Business.real_businesses.order(:name)
      @business = if params[:business_id].present?
        @businesses.find { |business| business.id == params[:business_id].to_i }
      else
        @businesses.first
      end
    end
  end
end
