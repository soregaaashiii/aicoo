class BusinessesController < ApplicationController
  before_action :set_business, only: %i[ show edit update destroy generate_ai_candidates import_google_api import_gsc import_ga4 update_data_source_settings ]

  # GET /businesses or /businesses.json
  def index
    @businesses = Business.real_businesses.includes(:business_execution_profile).order(:name)
    @business_integration_health = Aicoo::BusinessIntegrationHealth.new.call
    @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new
    @business_analytics_summaries = Aicoo::BusinessAnalyticsSummary.for_businesses(
      @businesses,
      health_result: @business_integration_health
    )
  end

  # GET /businesses/1 or /businesses/1.json
  def show
    @action_candidates = @business.action_candidates.by_recommendation
    @data_sources = @business.data_sources.includes(:data_imports).order(:name)
    @recent_data_imports = @business.data_imports.includes(:data_source).recent.limit(5)
    @recent_serp_analyses = @business.serp_analyses.order(analyzed_at: :desc).limit(10)
    @latest_daily_run = AicooDailyRun.recent.first
    @business_landing_pages = @business.aicoo_lab_landing_pages.order(updated_at: :desc)
    @landing_page_counts = @business.aicoo_lab_landing_pages.group(:public_status).count
    @business_playbook = @business.business_playbook
    @google_credential = AicooGoogleCredential.default&.reload
    @google_api_import_run = GoogleApiImportRun.latest_for(@business)
    @google_api_import_runs = GoogleApiImportRun.where(business: @business).recent.limit(8)
    @integration_health = Aicoo::BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == @business }
    @business_analytics_summary = Aicoo::BusinessAnalyticsSummary.new(@business, health: @integration_health).call
    @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new
    @business_data_source_statuses = @data_source_settings_presenter.business_statuses(@business)
    @auto_revision_run_logs = @business.auto_revision_run_logs.includes(:auto_revision_task).recent.limit(8)
    load_data_source_settings_context
  end

  # GET /businesses/new
  def new
    @business = Business.new(status: "idea")
  end

  # GET /businesses/1/edit
  def edit
    load_data_source_settings_context
    load_google_source_options
    @return_to = safe_return_to || edit_business_path(@business)
  end

  # POST /businesses or /businesses.json
  def create
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
    @business.destroy!

    respond_to do |format|
      format.html { redirect_to businesses_path, notice: "Business was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
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

  private
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
        :gsc_site_url,
        :project_key,
        :local_project_path,
        :repository_name,
        :auto_revision_mode
      ])
    end

    def load_data_source_settings_context
      DataSourceCostProfile.ensure_defaults!
      @data_source_cost_profiles = DataSourceCostProfile.ordered
      @business_data_source_settings_by_key = @business.business_data_source_settings.index_by(&:source_key)
      @data_source_settings_presenter = Aicoo::DataSourceSettingsPresenter.new(profiles: @data_source_cost_profiles, settings: @business.business_data_source_settings)
    end

    def load_google_source_options
      @ga4_property_options = google_source_options("ga4")
      @gsc_site_options = google_source_options("gsc")
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

    def ai_action_count
      count = params[:action_count].to_i
      [ 3, 5, 10 ].include?(count) ? count : 5
    end

    def enqueue_google_api_import!(source_types:, label:)
      if @business.system_business?
        redirect_to businesses_path, alert: "Google API取得は実事業だけが対象です。"
        return
      end

      credential = current_google_credential
      if google_credential_reauthentication_required?(credential)
        redirect_to business_path(@business, anchor: "business-google"),
                    alert: "Google OAuth Clientが変更されています。Google認証画面で再認証してください。"
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
          "google_credential_at_enqueue" => credential.diagnostic_snapshot
        }
      )
      log_google_api_import_credential!("enqueue", run:, credential:, source_types:)
      AicooAnalytics::BusinessGoogleApiImportJob.perform_later(run.id)
      redirect_to business_path(@business, anchor: "business-google"),
                  notice: "#{label}取得を開始しました。BusinessMetricDailyへの反映は完了後に表示されます。"
    end

    def current_google_credential
      AicooGoogleCredential.default&.reload
    end

    def google_credential_reauthentication_required?(credential)
      credential.blank? || !credential.connected?
    end

    def log_google_api_import_credential!(event, run:, credential:, source_types:)
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
          last_oauth_success_at: credential.last_oauth_success_at
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
