class BusinessLpIntegrationsController < ApplicationController
  before_action :set_business

  def show
    load_overview
  end

  def update
    Aicoo::LpIntegration::SettingsUpdater.new(
      business: @business,
      attributes: lp_integration_params
    ).call
    redirect_to business_lp_integration_path(@business), notice: "LP・計測連携設定を保存しました。"
  rescue ActiveRecord::RecordInvalid => e
    load_overview
    flash.now[:alert] = "設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    render :show, status: :unprocessable_content
  rescue ArgumentError => e
    load_overview
    flash.now[:alert] = e.message
    render :show, status: :unprocessable_content
  end

  def create_task
    result = Aicoo::LpIntegration::TaskCreator.new(business: @business).call
    notice = result.created ? "LP取り込みタスクを作成しました。Codexへの送信はまだ行っていません。" : "同じ設定の未完了タスクがあるため、既存タスクを表示します。"
    redirect_to auto_revision_task_path(result.task), notice:
  rescue ActiveRecord::RecordInvalid => e
    redirect_to business_lp_integration_path(@business), alert: "タスクを作成できませんでした: #{e.record.errors.full_messages.to_sentence}"
  rescue ArgumentError => e
    redirect_to business_lp_integration_path(@business), alert: e.message
  end

  def verify_production
    result = Aicoo::LpIntegration::ProductionVerifier.new(business: @business).call
    redirect_to business_lp_integration_path(@business), result.success ? { notice: result.message } : { alert: result.message }
  end

  private

  def set_business
    @business = Business.real_businesses.find(params.expect(:business_id))
  end

  def load_overview
    @lp_integration = Aicoo::LpIntegration::Overview.new(@business)
  end

  def lp_integration_params
    params.expect(lp_integration: [
      :lp_source_type,
      :lp_source_repository_url,
      :lp_source_branch,
      :lp_source_url,
      :app_repository_url,
      :app_branch,
      :app_framework,
      :marketing_root_path,
      :production_url,
      :render_service_name,
      :ga4_property_id,
      :ga4_measurement_id,
      :gsc_site_url,
      :activity_api_enabled,
      :integration_enabled,
      :auto_deploy_enabled,
      :manual_approval_required
    ])
  end
end
