module Admin
  class GoogleApiImportsController < ApplicationController
    def index
      @businesses = Business.includes(:business_data_source_settings).order(:name)
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
      if google_credential_reauthentication_required?
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
        fetched_days: GoogleApiImportRun.next_fetch_days_for(business, full_fetch: params[:full_fetch].present?)
      )
      AicooAnalytics::BusinessGoogleApiImportJob.perform_later(run.id)

      redirect_to admin_google_api_imports_path,
                  notice: "#{business.name}: Google API取得を開始しました。BusinessMetricDailyへの反映は完了後に表示されます。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_google_api_imports_path, alert: "Google APIから取得できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def google_credential_reauthentication_required?
      credential = AicooGoogleCredential.default
      credential.present? && !credential.connected?
    end
  end
end
