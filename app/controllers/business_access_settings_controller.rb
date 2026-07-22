class BusinessAccessSettingsController < ApplicationController
  before_action :set_business

  def update_service
    Aicoo::BusinessAccessSettingsUpdater.new(@business).update_service!(service_params)
    redirect_to_access_section("Service設定を保存しました。")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to_access_section("Service設定を保存できませんでした: #{error_message(e)}", alert: true)
  end

  def update_landing_page
    landing_page = Aicoo::BusinessAccessSettingsUpdater.new(@business).update_landing_page!(landing_page_params)
    if params[:commit_action] == "create_task"
      result = Aicoo::LpIntegration::LandingPageTaskCreator.new(business: @business, landing_page:).call
      message = result.created ? "LP設定を保存し、LP取り込みタスクを作成しました。" : "LP設定を保存しました。同じ設定の未完了タスクがあります。"
      redirect_to_access_section(message)
    else
      redirect_to_access_section("LP設定を保存しました。")
    end
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to_access_section("LP設定を保存できませんでした: #{error_message(e)}", alert: true)
  end

  def update_campaign
    Aicoo::BusinessAccessSettingsUpdater.new(@business).update_campaign!(campaign_params)
    redirect_to_access_section("Campaign設定を保存しました。")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to_access_section("Campaign設定を保存できませんでした: #{error_message(e)}", alert: true)
  end

  def destroy_campaign
    Aicoo::BusinessAccessSettingsUpdater.new(@business).archive_campaign!(params.expect(:campaign_id))
    redirect_to_access_section("Campaignをアーカイブしました。")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
    redirect_to_access_section("Campaignをアーカイブできませんでした: #{error_message(e)}", alert: true)
  end

  def create_landing_page_task
    landing_page = landing_page_registry.find!(params.expect(:landing_page_id))
    result = Aicoo::LpIntegration::LandingPageTaskCreator.new(business: @business, landing_page:).call
    message = result.created ? "LP取り込みタスクを作成しました。" : "同じ設定の未完了タスクがあります。"
    redirect_to_access_section(message)
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to_access_section("LP取り込みタスクを作成できませんでした: #{error_message(e)}", alert: true)
  end

  def destroy_landing_page
    landing_page_registry.archive!(params.expect(:landing_page_id))
    redirect_to_access_section("LPを削除しました。")
  rescue ActiveRecord::RecordNotFound
    redirect_to_access_section("LPが見つかりません。", alert: true)
  end

  def improve_landing_page
    landing_page = landing_page_registry.find!(params.expect(:landing_page_id))
    result = Aicoo::LpIntegration::LandingPageImprovementFlow.new(
      business: @business,
      landing_page:
    ).call
    if result.task
      message = result.created ? "LPを分析し、承認待ちの改善タスクを作成しました。" : "同じ改善タスクが承認または実行待ちです。"
      redirect_to_access_section(message)
    else
      redirect_to_access_section("LPを分析しました。#{result.analysis.reason}", alert: true)
    end
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to_access_section("LPを分析できませんでした: #{error_message(e)}", alert: true)
  end

  def update_landing_page_status
    landing_page_registry.update_status!(params.expect(:landing_page_id), params.expect(:public_status))
    redirect_to_access_section("LPの公開状態を更新しました。")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
    redirect_to_access_section("LPの公開状態を更新できませんでした: #{error_message(e)}", alert: true)
  end

  def update_production
    Aicoo::BusinessAccessSettingsUpdater.new(@business).update_production!(production_params)
    redirect_to_access_section("本番設定を保存しました。")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to_access_section("本番設定を保存できませんでした: #{error_message(e)}", alert: true)
  end

  def update_measurement
    Aicoo::BusinessAccessSettingsUpdater.new(@business).update_measurement!(measurement_params)
    redirect_to_access_section("LP共通の計測設定を保存しました。")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to_access_section("計測設定を保存できませんでした: #{error_message(e)}", alert: true)
  end

  def verify_production
    result = Aicoo::LpIntegration::ProductionVerifier.new(business: @business).call
    redirect_to_access_section(result.message, alert: !result.success)
  end

  private

  def set_business
    @business = Business.real_businesses.find(params.expect(:business_id))
  end

  def service_params
    params.expect(service_access: %i[
      business_service_id name service_url domain github_repository branch framework render_service_name
      health_check_url deploy_target activity_api_endpoint auto_deploy_enabled status
    ])
  end

  def landing_page_params
    params.expect(lp_access: %i[
      landing_page_id campaign_id name source_type repository_url branch lovable_project_url url public_status
      ga4_page_path cta current_conversion_rate improvement_target cloudflare_preview_url cloudflare_deploy_status
      ab_test_name ab_variant ab_status ab_winner ab_win_rate
    ])
  end

  def campaign_params
    params.expect(campaign_access: %i[
      campaign_id name campaign_type status starts_on ends_on budget_yen target_conversions
      target_cpa_yen ga4_filter gsc_filter notes
    ])
  end

  def production_params
    params.expect(production_access: %i[
      production_url health_check_url render_service_name deploy_target auto_deploy_enabled
    ])
  end

  def measurement_params
    params.expect(measurement_access: %i[
      public_url ga4_measurement_id ga4_property_id gsc_site_url activity_api_enabled
      cloudflare_project_name cloudflare_production_url cloudflare_branch
    ])
  end

  def landing_page_registry
    @landing_page_registry ||= Aicoo::LpIntegration::LandingPageRegistry.new(business: @business)
  end

  def redirect_to_access_section(message, alert: false)
    options = alert ? { alert: message } : { notice: message }
    redirect_to business_path(@business, anchor: "business-access-urls"), options
  end

  def error_message(error)
    return error.record.errors.full_messages.to_sentence if error.respond_to?(:record)

    error.message
  end
end
