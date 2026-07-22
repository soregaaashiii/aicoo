class BusinessesController < ApplicationController
  before_action :set_business, only: %i[
    show edit update destroy generate_ai_candidates import_google_api import_gsc import_ga4
    google_settings update_google_settings
    update_data_source_settings promote_to_mvp promote_to_production promote_to_scaling update_resource_status
    restore permanently_destroy
  ]

  DELETION_REASONS = %w[
    SERP誤生成
    既存事業との重複
    需要なし
    検証不要
    誤登録
    その他
  ].freeze

  # GET /businesses or /businesses.json
  def index
    Aicoo::MemoryDiagnostics.measure("BusinessesController#index", context: memory_diagnostics_context) do
      @businesses = Aicoo::MemoryDiagnostics.measure("BusinessesController#index.business_list", context: memory_diagnostics_context) do
        businesses = Business.real_businesses.includes(:business_execution_profile).order(:name)
        businesses = businesses.where(status: "exploring") if params[:filter] == "exploring"
        businesses = businesses.select(&:serp_generated?) if params[:filter] == "serp"
        businesses
      end
      @active_tab = params[:tab].presence_in(%w[businesses serp_candidates]) || "businesses"
      @deletion_reasons = DELETION_REASONS
      @serp_new_business_board = Aicoo::NewBusinessCandidateBoard.call(limit: 50)
      @business_integration_health = Aicoo::MemoryDiagnostics.measure("Aicoo::BusinessIntegrationHealth#call", context: memory_diagnostics_context) do
        Aicoo::BusinessIntegrationHealth.new.call
      end
      @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new
      @business_analytics_summaries = Aicoo::MemoryDiagnostics.measure("Aicoo::BusinessAnalyticsSummary.for_businesses", context: memory_diagnostics_context(business_count: @businesses.size)) do
        Aicoo::BusinessAnalyticsSummary.for_businesses(
          @businesses,
          health_result: @business_integration_health
        )
      end
      @business_expected_values = Aicoo::MemoryDiagnostics.measure("BusinessesController#index.business_expected_values", context: memory_diagnostics_context(business_count: @businesses.size)) do
        @businesses.index_with { |business| Aicoo::BusinessExpectedValue.call(business) }
      end
    end
  end

  def deleted
    @businesses = Business.deleted.order(deleted_at: :desc, updated_at: :desc)
    @deletion_reasons = DELETION_REASONS
  end

  # GET /businesses/1 or /businesses/1.json
  def show
    @business_prototypes = @business.business_prototypes.recent
    @action_candidates = @business.action_candidates.by_recommendation
    @ai_improvement_action_candidates = @business.action_candidates
                                                   .active_for_ranking
                                                   .where.not(action_type: "data_preparation")
                                                   .by_recommendation
                                                   .limit(10)
    @ai_improvement_auto_revision_tasks = @business.auto_revision_tasks.active.by_priority.limit(10)
    @business_codex_waiting_tasks = @business.auto_revision_tasks
                                           .where(status: %w[ready_for_codex queued approved])
                                           .by_priority
                                           .limit(5)
    @data_sources = @business.data_sources.includes(:data_imports).order(:name)
    @recent_data_imports = @business.data_imports.includes(:data_source).recent.limit(5)
    @recent_serp_analyses = @business.serp_analyses.order(analyzed_at: :desc).limit(10)
    @latest_daily_run = AicooDailyRun.recent.first
    @business_landing_pages = @business.aicoo_lab_landing_pages.order(updated_at: :desc)
    @landing_page_counts = @business.aicoo_lab_landing_pages.group(:public_status).count
    @lovable_version_repository = Aicoo::Lovable::VersionRepository.new(business: @business)
    @lovable_current_version = @lovable_version_repository.current
    @lovable_published_version = @lovable_version_repository.published
    @lovable_published_learning = if @lovable_published_version
      Aicoo::Lovable::LearningSummary.new(
        business: @business,
        generation_run: @lovable_published_version
      ).call
    end
    @lp_evaluations = Aicoo::LpEvaluationSummary.for_business(@business)
    @lp_evaluations_by_id = @lp_evaluations.index_by { |row| row.landing_page.id }
    @mvp_ready_check = Aicoo::MvpReadyCheck.new(@business, @lp_evaluations).call
    @business_services = @business.business_services.recent
    @mvp_evaluations = Aicoo::MvpEvaluationSummary.for_business(@business)
    @mvp_evaluations_by_service_id = @mvp_evaluations.index_by { |row| row.business_service.id }
    @production_ready_check = Aicoo::ProductionReadyCheck.new(@business, @mvp_evaluations).call
    @scaling_evaluation = Aicoo::ScalingEvaluationSummary.for_business(@business)
    @scaling_ready_check = Aicoo::ScalingReadyCheck.new(@business, @scaling_evaluation).call
    @resource_summary = Aicoo::ResourceSummary.for_business(@business)
    @attention_score = Aicoo::AttentionScore.for_business(@business)
    @business_timeline = Aicoo::BusinessTimeline.new(@business).call
    @recent_activity_logs = @business.business_activity_logs.recent.limit(10)
    @recent_action_executions = ActionExecution.joins(:action_candidate)
                                               .where(action_candidates: { business_id: @business.id })
                                               .recent
                                               .limit(10)
    @recent_action_results = @business.action_results.order(created_at: :desc).limit(10)
    @business_playbook = @business.business_playbook
    @google_credential = AicooGoogleCredential.default&.reload
    @google_api_import_run = GoogleApiImportRun.latest_for(@business)
    @google_api_import_runs = GoogleApiImportRun.where(business: @business).recent.limit(8)
    @integration_health = Aicoo::BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }
    @ga4_connection_summary = Aicoo::BusinessGoogleConnectionSummary.new(@business, source_key: "ga4", health: @integration_health).call
    @gsc_connection_summary = Aicoo::BusinessGoogleConnectionSummary.new(@business, source_key: "gsc", health: @integration_health).call
    @system_statuses = business_system_statuses(@business, %w[ga4 gsc serp openai codex daily_run traffic pipeline learning business_health])
    @google_credential = @ga4_connection_summary.setting&.google_credential || @gsc_connection_summary.credential || AicooGoogleCredential.default
    @business_analytics_summary = Aicoo::BusinessAnalyticsSummary.new(@business, health: @integration_health).call
    @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new
    @business_data_source_statuses = @data_source_settings_presenter.business_statuses(@business)
    @data_source_policy = Aicoo::DataSourcePolicy.for(@business)
    load_suelog_database_status
    @auto_revision_run_logs = @business.auto_revision_run_logs.includes(:auto_revision_task).recent.limit(8)
    @pipeline_run = latest_pipeline_run_for(@business)
    @pipeline_recovery_logs = @pipeline_run.persisted? ? @pipeline_run.pipeline_recovery_logs.recent.limit(20) : PipelineRecoveryLog.none
    load_data_source_settings_context
  end

  # GET /businesses/new
  def new
    @business = Business.new(status: "idea")
    @registration_mode = params[:registration_mode].presence_in(Aicoo::BusinessRegistration::MODES)
    @registration_values = {}
  end

  # GET /businesses/1/edit
  def edit
    load_data_source_settings_context
    load_google_source_options
    @data_source_policy = Aicoo::DataSourcePolicy.for(@business)
    @return_to = safe_return_to || edit_business_path(@business)
  end

  def google_settings
    load_business_google_settings_context
  end

  # POST /businesses or /businesses.json
  def create
    return create_registration_v2 if params[:registration_mode].present?

    @business = Business.new(business_params)

    respond_to do |format|
      if @business.save
        format.html { redirect_to @business, notice: "Business was successfully created." }
        format.json { render :show, status: :created, location: @business }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @business.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /businesses/1 or /businesses/1.json
  def update
    respond_to do |format|
      if @business.update(business_params)
        format.html { redirect_to safe_return_to || @business, notice: "Business was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @business }
      else
        format.html do
          load_data_source_settings_context
          render :edit, status: :unprocessable_content
        end
        format.json { render json: @business.errors, status: :unprocessable_content }
      end
    end
  end

    def update_data_source_settings
      DataSourceCostProfile.ensure_defaults!

      business_data_source_setting_params.each do |source_key, attributes|
        setting = BusinessDataSourceSetting.find_or_initialize_by(business: @business, source_key:)
        connection_fields = setting.connection_field_values.merge(attributes[:connection_fields].to_h)
        source_binding = setting.metadata.to_h.fetch("source_binding", {}).merge(attributes[:source_binding].to_h)
        connection_status = auto_connection_status_for(profile_key: source_key, attributes:, connection_fields:)
        property_identifier = if source_key.in?(%w[gsc ga4])
          google_identifier_for(source_key, attributes:, connection_fields:)
        else
          attributes[:property_identifier]
        end
        setting.assign_attributes(
          enabled: ActiveModel::Type::Boolean.new.cast(attributes[:enabled]),
          connection_status:,
        external_account_id: attributes[:external_account_id],
        property_identifier:,
          endpoint_url: attributes[:endpoint_url],
          credential_reference: attributes[:credential_reference],
          notes: attributes[:notes],
          metadata: setting.metadata.merge(
            "connection_fields" => connection_fields,
            "source_binding" => source_binding
          )
        )
        setting.save!
      end
      sync_business_google_site!

    redirect_to safe_return_to || edit_business_path(@business, anchor: "data-source-link-settings"),
                notice: "Data Source紐付け設定を保存しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to safe_return_to || edit_business_path(@business, anchor: "data-source-link-settings"),
                alert: "Data Source紐付け設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
  end

  # DELETE /businesses/1 or /businesses/1.json
  def destroy
    @business.soft_delete!(
      reason: deletion_reason,
      actor: "owner",
      source: "business_detail"
    )

    respond_to do |format|
      format.html { redirect_to businesses_path, notice: "Businessを削除しました。関連データは保持され、削除済み一覧から復元できます。", status: :see_other }
      format.json { render json: { deleted: true, business_id: @business.id } }
    end
  end

  def restore
    @business.restore_from_soft_delete!(actor: "owner")
    redirect_to business_path(@business), notice: "Businessを復元しました。"
  end

  def permanently_destroy
    unless @business.deleted?
      redirect_to deleted_businesses_path, alert: "完全削除できません: 論理削除済みBusinessだけ完全削除できます。"
      return
    end

    unless params[:confirmation_name].to_s == @business.name
      redirect_to deleted_businesses_path, alert: "完全削除できません: Business名が一致しません。"
      return
    end

    record_permanent_deletion_audit!(@business)
    ApprovalLog.where(business_id: @business.id).update_all(business_id: nil, updated_at: Time.current)
    @business.destroy!
    redirect_to deleted_businesses_path, notice: "Businessを完全削除しました。"
  end

  def bulk_delete
    ids = selected_business_ids
    if ids.empty?
      redirect_to businesses_path, alert: "削除するBusinessを選択してください。"
      return
    end

    businesses = Business.real_businesses.where(id: ids)
    deleted_count = 0
    Business.transaction do
      businesses.find_each do |business|
        business.soft_delete!(
          reason: deletion_reason,
          actor: "owner",
          source: "business_bulk_delete"
        )
        deleted_count += 1
      end
    end

    redirect_to businesses_path, notice: "#{deleted_count}件の事業を削除しました。"
  end

  def bulk_restore
    ids = selected_business_ids
    if ids.empty?
      redirect_to deleted_businesses_path, alert: "復元するBusinessを選択してください。"
      return
    end

    businesses = Business.deleted.where(id: ids)
    businesses.find_each { |business| business.restore_from_soft_delete!(actor: "owner") }

    redirect_to deleted_businesses_path, notice: "#{businesses.count}件のBusinessを復元しました。"
  end

  def generate_ai_candidates
    result = AiActionGeneratorService.new(@business, action_count: ai_action_count).call

    redirect_to action_candidates_path, notice: "AI generated #{result.action_candidates.size} action candidates for #{@business.name}."
  rescue OpenaiResponsesClient::MissingApiKeyError => e
    redirect_to @business, alert: e.message
  rescue OpenaiResponsesClient::Error, ActiveRecord::RecordInvalid => e
    redirect_to @business, alert: "AI candidate generation failed: #{e.message}"
  end

  def import_gsc
    enqueue_google_api_import!(source_types: %w[gsc], label: "GSC")
  end

  def import_google_api
    enqueue_google_api_import!(source_types: %w[gsc ga4], label: "Google API")
  end

  def import_ga4
    enqueue_google_api_import!(source_types: %w[ga4], label: "GA4")
  end

  def update_google_settings
    settings = google_settings_params
    credential = AicooGoogleCredential.find_by(id: settings[:google_credential_id].presence)
    ActiveRecord::Base.transaction do
      upsert_google_business_data_source_setting!(
        source_key: "ga4",
        enabled: settings[:ga4_enabled],
        identifier_key: "property_id",
        identifier: settings[:ga4_property_id],
        credential:
      )
      upsert_google_business_data_source_setting!(
        source_key: "gsc",
        enabled: settings[:gsc_enabled],
        identifier_key: "site_url",
        identifier: settings[:gsc_site_url],
        credential:
      )
      Aicoo::LpIntegration::GoogleMeasurementUpdater.new(
        business: @business,
        measurement_id: settings[:ga4_measurement_id]
      ).call
      sync_business_google_site!
      sync_business_google_analytics_credentials!(credential)
    end

    redirect_to google_settings_business_path(@business), notice: "Business個別Google設定を保存しました"
  rescue ActiveRecord::RecordInvalid => e
    load_business_google_settings_context
    flash.now[:alert] = "Business個別Google設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    render :google_settings, status: :unprocessable_content
  end

  def promote_to_mvp
    result = Aicoo::MvpPromotion.new(
      business: @business,
      landing_page_id: params.expect(:landing_page_id),
      operator: "owner"
    ).call

    redirect_to business_path(result.business, anchor: "business-services"),
                notice: "MVP開発へ進めました。AutoRevisionTask ##{result.auto_revision_task.id} を作成しました。"
  rescue ActiveRecord::RecordNotFound => e
    redirect_to business_path(@business, anchor: "business-lp"), alert: "MVP昇格に失敗しました: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to business_path(@business, anchor: "business-lp"),
                alert: "MVP昇格に失敗しました: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
  rescue StandardError => e
    redirect_to business_path(@business, anchor: "business-lp"), alert: "MVP昇格に失敗しました: #{e.message}"
  end

  def promote_to_production
    result = Aicoo::ProductionPromotion.new(
      business: @business,
      business_service_id: params.expect(:business_service_id),
      operator: "owner"
    ).call

    redirect_to business_path(result.business, anchor: "business-services"),
                notice: "本番運用へ進めました。AutoRevisionTask ##{result.auto_revision_task.id} を作成しました。"
  rescue ActiveRecord::RecordNotFound => e
    redirect_to business_path(@business, anchor: "business-services"), alert: "本番昇格に失敗しました: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to business_path(@business, anchor: "business-services"),
                alert: "本番昇格に失敗しました: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
  rescue StandardError => e
    redirect_to business_path(@business, anchor: "business-services"), alert: "本番昇格に失敗しました: #{e.message}"
  end

  def promote_to_scaling
    result = Aicoo::ScalingPromotion.new(business: @business, operator: "owner").call

    redirect_to business_path(result.business, anchor: "business-scaling"),
                notice: "Scalingへ進めました。AutoRevisionTask ##{result.auto_revision_task.id} を作成しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to business_path(@business, anchor: "business-scaling"),
                alert: "Scaling昇格に失敗しました: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
  rescue StandardError => e
    redirect_to business_path(@business, anchor: "business-scaling"), alert: "Scaling昇格に失敗しました: #{e.message}"
  end

  def update_resource_status
    new_status = params.expect(:resource_status).to_s
    reason = params[:reason].presence || "Owner承認による運用状態変更"
    unless new_status.in?(Business::RESOURCE_STATUSES)
      redirect_to business_path(@business, anchor: "business-resource"), alert: "運用状態を変更できませんでした: 不正な状態です。"
      return
    end

    @business.change_resource_status!(new_status, reason:, operator: "owner")
    redirect_to business_path(@business, anchor: "business-resource"), notice: "運用状態を#{new_status}へ変更しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to business_path(@business, anchor: "business-resource"),
                alert: "運用状態を変更できませんでした: #{e.record.errors.full_messages.to_sentence}"
  end

  private

    def create_registration_v2
      values = business_registration_params
      result = Aicoo::BusinessRegistration.new(
        mode: params[:registration_mode],
        name: values[:name],
        description: values[:description],
        prototype_type: values[:prototype_type],
        prototype_location: values[:prototype_location]
      ).call

      redirect_to result.business,
                  notice: "#{result.business.name}を登録しました。初期解析と今日やることの準備を開始しています。"
    rescue Aicoo::BusinessRegistration::InvalidRegistration, ActiveRecord::RecordInvalid => e
      @business = Business.new(name: values&.dig(:name), description: values&.dig(:description), status: "idea")
      @registration_mode = params[:registration_mode].to_s
      @registration_values = values.to_h
      @registration_errors = if e.respond_to?(:record)
        e.record.errors.full_messages
      else
        [ e.message ]
      end
      render :new, status: :unprocessable_content
    end

    def business_registration_params
      params.fetch(:registration, {}).permit(:name, :description, :prototype_type, :prototype_location)
    end

  def selected_business_ids
    Array(params[:business_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
  end

  def deletion_reason
    params[:deletion_reason].presence_in(DELETION_REASONS) || params[:deletion_reason].presence || "その他"
  end

  def record_permanent_deletion_audit!(business)
    ApprovalLog.create!(
      approvable: business,
      action: "permanent_delete",
      source: "businesses_controller",
      operator: "owner",
      approved_at: Time.current,
      common_previous_status: "deleted",
      common_new_status: "deleted",
      previous_status: business.status,
      new_status: "permanent_deleted",
      message: "Businessを完全削除しました: #{business.name}",
      metadata: {
        business_id: business.id,
        business_name: business.name,
        deletion_reason: business.deletion_reason,
        deleted_at: business.deleted_at&.iso8601
      }
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end
    def load_suelog_database_status
      return unless Aicoo::CandidateGenerators::SuelogGenerator.target?(@business)

      @suelog_db_health = Aicoo::ExternalSources::SuelogHealthCheck.call
      @suelog_db_candidate_counts = @business.action_candidates
        .where(generation_source: "suelog_db", created_at: 24.hours.ago..Time.current)
        .group(:action_type)
        .count
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_business
      @business = Business.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def business_params
      params.expect(business: [
        :name,
        :description,
        :status,
        :business_type,
        :gsc_site_url,
        :project_key,
        :local_project_path,
        :repository_name,
        :lifecycle_stage,
        :resource_status,
        :resource_status_reason,
        :next_review_on,
        :auto_revision_mode,
        :auto_deploy_mode,
        :auto_build_enabled,
        :auto_build_requires_approval,
        :auto_build_risk_level,
        :new_lp_auto_deploy_enabled,
        :auto_deploy_suspended
      ])
    end

    def load_data_source_settings_context
      DataSourceCostProfile.ensure_defaults!
      @data_source_cost_profiles = DataSourceCostProfile.ordered
      @business_data_source_settings_by_key = @business.business_data_source_settings.index_by(&:source_key)
      @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new(profiles: @data_source_cost_profiles, settings: @business.business_data_source_settings)
      @data_source_policy = Aicoo::DataSourcePolicy.for(@business)
    end

    def load_google_source_options
      @ga4_property_options = google_source_options("ga4")
      @gsc_site_options = google_source_options("gsc")
    end

    def load_business_google_settings_context
      @google_credentials = AicooGoogleCredential.enabled.recent
      @integration_health = Aicoo::BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }
      @ga4_connection_summary = Aicoo::BusinessGoogleConnectionSummary.new(@business, source_key: "ga4", health: @integration_health).call
      @gsc_connection_summary = Aicoo::BusinessGoogleConnectionSummary.new(@business, source_key: "gsc", health: @integration_health).call
      @system_statuses = business_system_statuses(@business, %w[ga4 gsc serp openai codex])
      @google_credential = selected_business_google_credential ||
                           @ga4_connection_summary.credential ||
                           @gsc_connection_summary.credential ||
                           AicooGoogleCredential.default
      load_google_source_options
    end

    def google_source_options(source_type)
      rows = AnalyticsSourceSetting
        .where(source_type:, enabled: true)
        .order(:name, :created_at)
        .filter_map do |setting|
          identifier = source_type == "ga4" ? setting.property_id : setting.site_url
          next if identifier.blank?

          [ "#{setting.name} - #{identifier}", identifier ]
        end

      site_rows = AicooAnalyticsSite
        .where.not(source_type == "ga4" ? { ga4_property_id: [ nil, "" ] } : { gsc_site_url: [ nil, "" ] })
        .order(:name, :created_at)
        .filter_map do |site|
          identifier = source_type == "ga4" ? site.ga4_property_id : site.gsc_site_url
          next if identifier.blank?

          [ "#{site.name} - #{identifier}", identifier ]
        end

      (rows + site_rows).uniq { |_label, value| value }
    end

    def business_data_source_setting_params
      params.fetch(:business_data_source_settings, {}).permit!.to_h
    end

    def google_settings_params
      params.expect(google_settings: %i[
        google_credential_id
        ga4_property_id
        ga4_measurement_id
        gsc_site_url
        ga4_enabled
        gsc_enabled
      ])
    end

    def upsert_google_business_data_source_setting!(source_key:, enabled:, identifier_key:, identifier:, credential:)
      setting = BusinessDataSourceSetting.find_or_initialize_by(business: @business, source_key:)
      enabled_value = ActiveModel::Type::Boolean.new.cast(enabled)
      clean_identifier = identifier.to_s.strip
      connection_fields = setting.connection_field_values.merge(identifier_key => clean_identifier)
      metadata = setting.metadata.to_h.merge(
        "connection_fields" => connection_fields,
        "source_binding" => setting.metadata.to_h.fetch("source_binding", {}).merge("use_global" => "0"),
        "google_credential_id" => credential&.id
      )
      setting.assign_attributes(
        enabled: enabled_value,
        connection_status: google_connection_status_for(enabled: enabled_value, identifier: clean_identifier, credential:),
        property_identifier: clean_identifier,
        credential_reference: credential&.name,
        metadata:
      )
      setting.save!
    end

    def google_connection_status_for(enabled:, identifier:, credential:)
      return "unlinked" unless enabled
      return "unlinked" if identifier.blank?

      credential&.connected? ? "linked" : "needs_attention"
    end

    def selected_business_google_credential
      explicit_id = @business.business_data_source_settings
        .where(source_key: %w[ga4 gsc])
        .filter_map { |setting| setting.metadata.to_h["google_credential_id"].presence }
        .first
      AicooGoogleCredential.find_by(id: explicit_id)
    end

    def auto_connection_status_for(profile_key:, attributes:, connection_fields:)
      return attributes[:connection_status] unless profile_key.in?(%w[gsc ga4])
      return "unlinked" unless ActiveModel::Type::Boolean.new.cast(attributes[:enabled])

      identifier = google_identifier_for(profile_key, attributes:, connection_fields:)
      return "unlinked" if identifier.blank?

      google_connection_available? ? "linked" : "needs_attention"
    end

    def google_identifier_for(profile_key, attributes:, connection_fields:)
      key = profile_key == "gsc" ? "site_url" : "property_id"
      connection_fields[key].presence || attributes[:property_identifier].presence
    end

    def google_connection_available?
      AicooGoogleCredential.default&.connected? ||
        ENV["GOOGLE_CLIENT_ID"].present? &&
          ENV["GOOGLE_CLIENT_SECRET"].present? &&
          ENV["GOOGLE_REFRESH_TOKEN"].present?
    end

    def sync_business_google_site!
      gsc_setting = @business.business_data_source_settings.find_by(source_key: "gsc")
      ga4_setting = @business.business_data_source_settings.find_by(source_key: "ga4")
      gsc_site_url = gsc_setting&.connection_field_value("site_url").presence || gsc_setting&.property_identifier.presence || @business.gsc_site_url.presence
      ga4_property_id = ga4_setting&.connection_field_value("property_id").presence || ga4_setting&.property_identifier.presence
      return if gsc_site_url.blank? && ga4_property_id.blank?

      @business.update!(gsc_site_url:) if gsc_site_url.present? && @business.gsc_site_url != gsc_site_url
      site = AicooAnalyticsSite.where(business: @business).recent.first || AicooAnalyticsSite.new(business: @business)
      site.assign_attributes(
        name: @business.name,
        gsc_site_url: gsc_site_url.presence || site.gsc_site_url,
        ga4_property_id: ga4_property_id.presence || site.ga4_property_id,
        authentication_mode: "shared",
        enabled: true
      )
      site.save!
    end

    def sync_business_google_analytics_credentials!(credential)
      site = AicooAnalyticsSite.where(business: @business).recent.first
      return unless site

      sync_google_source_setting_credential!(site.gsc_setting, "gsc", credential)
      sync_google_source_setting_credential!(site.ga4_setting, "ga4", credential)
    end

    def sync_google_source_setting_credential!(setting, source_key, credential)
      business_setting = @business.business_data_source_settings.find_by(source_key:)
      return unless setting && business_setting

      setting.update!(
        enabled: business_setting.enabled?,
        authentication_mode: "shared",
        google_credential: credential
      )
    end

    def ai_action_count
      count = params[:action_count].to_i
      [ 3, 5, 10 ].include?(count) ? count : 5
    end

    def enqueue_google_api_import!(source_types:, label:)
      if @business.system_business?
        redirect_to businesses_path, alert: "Google API取得は実事業だけが対象です。"
        return
      end

      auto_link_business_google_defaults!(source_types:)
      credential_status = google_credential_status_for_sources(source_types)
      if credential_status[:credential].blank? || credential_status[:reauthentication_required]
        redirect_to business_path(@business, anchor: "business-google"),
                    alert: "#{credential_status[:label]}のGoogle Credentialを確認してください。Business別Google設定でCredential選択または再認証が必要です。"
        return
      end

      if GoogleApiImportRun.running_for?(@business)
        redirect_to business_path(@business, anchor: "business-google"), alert: "#{@business.name} はすでに取得中です。"
        return
      end

      run = GoogleApiImportRun.create!(
        business: @business,
        status: "queued",
        source_types:,
        fetched_days: GoogleApiImportRun.next_fetch_days_for(@business, full_fetch: params[:full_fetch].present?),
        metadata: {
          "google_credential_at_enqueue" => credential_status[:credential].diagnostic_snapshot,
          "google_setting_sources_at_enqueue" => credential_status[:setting_sources]
        }
      )
      log_google_api_import_credential!(
        "enqueue",
        run:,
        credential: credential_status[:credential],
        source_types:,
        setting_sources: credential_status[:setting_sources]
      )
      AicooAnalytics::BusinessGoogleApiImportJob.perform_later(run.id)
      redirect_to business_path(@business, anchor: "business-google"),
                  notice: "#{label}取得を開始しました。BusinessMetricDailyへの反映は完了後に表示されます。"
    end

    def google_credential_reauthentication_required?(credential)
      credential.blank? || !credential.connected?
    end

    def google_credential_status_for_sources(source_types)
      summaries = source_types.index_with do |source_type|
        Aicoo::BusinessGoogleConnectionSummary.new(@business, source_key: source_type).call
      end
      missing = summaries.find { |_source_type, summary| google_credential_reauthentication_required?(summary.credential) }
      summary = missing&.last || summaries.values.first

      {
        credential: summary&.credential&.reload,
        reauthentication_required: missing.present?,
        label: missing ? missing.first.upcase : source_types.map(&:upcase).join("/"),
        setting_sources: summaries.transform_values(&:setting_source)
      }
    end

    def business_system_statuses(business, keys)
      keys.index_with { |key| Aicoo::SystemStatusResolver.call(key, business:) }
    end

    def latest_pipeline_run_for(business)
      AicooPipelineRun.where(pipeline_type: "business", business:).recent.first ||
        AicooPipelineRun.new(
          pipeline_type: "business",
          business:,
          status: "waiting",
          current_stage: "discovery",
          next_stage: "score",
          started_at: business.created_at,
          stage_states: {},
          metadata: {}
        )
    end

    def auto_link_business_google_defaults!(source_types: %w[gsc ga4])
      Aicoo::BusinessGoogleDefaultLinker.call(@business, source_types:)
    rescue StandardError => e
      Rails.logger.warn("[BusinessesController] google default auto link failed business_id=#{@business.id}: #{e.class}: #{e.message}")
    end

    def log_google_api_import_credential!(event, run:, credential:, source_types:, setting_sources: {})
      Rails.logger.info(
        "Business Google API import #{event} " \
        "#{{
          business_id: @business.id,
          business_name: @business.name,
          run_id: run.id,
          source_types:,
          credential_record_id: credential.id,
          credential_client_id: credential.client_id,
          credential_project_id: credential.google_cloud_project_id,
          credential_project_number: credential.oauth_project_number,
          refresh_token_saved: credential.refresh_token.present?,
          access_token_saved: credential.access_token.present?,
          last_oauth_success_at: credential.last_oauth_success_at,
          setting_sources:
        }.compact.to_json}"
      )
    end

    def safe_return_to
      raw_return_to = params[:return_to].to_s
      return if raw_return_to.blank?

      uri = URI.parse(raw_return_to)
      return if uri.host.present? || uri.scheme.present?

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end
end
