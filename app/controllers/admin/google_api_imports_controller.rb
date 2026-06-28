module Admin
  class GoogleApiImportsController < ApplicationController
    def index
      @businesses = Business.real_businesses.includes(:business_data_source_settings).order(:name)
      @google_credential = AicooGoogleCredential.default&.reload
      @google_api_import_runs_by_business_id = GoogleApiImportRun
        .where(business_id: @businesses.map(&:id))
        .recent
        .group_by(&:business_id)
        .transform_values(&:first)
      @business_integration_health = Aicoo::BusinessIntegrationHealth.new.call
      @business_analytics_summaries = Aicoo::BusinessAnalyticsSummary.for_businesses(
        @businesses,
        health_result: @business_integration_health
      )
    end

    def create
      business = Business.find(params.expect(:business_id))
      credential = current_google_credential
      if google_credential_reauthentication_required?(credential)
        redirect_to admin_google_api_imports_path,
                    alert: "Google OAuth Clientが変更されています。Google認証画面で再認証してください。"
        return
      end

      if GoogleApiImportRun.running_for?(business)
        redirect_to admin_google_api_imports_path, alert: "#{business.name} はすでに取得中です。"
        return
      end

      run = GoogleApiImportRun.create!(
        business:,
        status: "queued",
        source_types: %w[gsc ga4],
        fetched_days: GoogleApiImportRun.next_fetch_days_for(business, full_fetch: params[:full_fetch].present?),
        metadata: {
          "google_credential_at_enqueue" => credential.diagnostic_snapshot
        }
      )
      log_google_api_import_credential!("enqueue", business:, run:, credential:)
      AicooAnalytics::BusinessGoogleApiImportJob.perform_later(run.id)

      redirect_to admin_google_api_imports_path,
                  notice: "#{business.name}: Google API取得を開始しました。BusinessMetricDailyへの反映は完了後に表示されます。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_google_api_imports_path, alert: "Google APIから取得できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def current_google_credential
      AicooGoogleCredential.default&.reload
    end

    def google_credential_reauthentication_required?(credential)
      credential.blank? || !credential.connected?
    end

    def log_google_api_import_credential!(event, business:, run:, credential:)
      Rails.logger.info(
        "Google API import #{event} " \
        "#{{
          business_id: business.id,
          business_name: business.name,
          run_id: run.id,
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
  end
end
