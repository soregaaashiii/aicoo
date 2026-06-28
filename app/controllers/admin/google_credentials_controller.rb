module Admin
  class GoogleCredentialsController < ApplicationController
    before_action :set_credential, only: %i[edit update connect]

    def index
      @credentials = AicooGoogleCredential.recent
      @credential = AicooGoogleCredential.new(name: "AICOO共通Google認証", enabled: true)
    end

    def new
      @credential = AicooGoogleCredential.new(name: "AICOO共通Google認証", enabled: true)
    end

    def create
      @credential = AicooGoogleCredential.new(credential_params)
      if @credential.save
        if params[:connect_after_save].present?
          redirect_to connect_admin_google_credential_path(@credential), notice: "Google認証を保存しました。続けてGoogleと接続します。"
        else
          redirect_to admin_google_credentials_path, notice: "Google認証を保存しました"
        end
      else
        @credentials = AicooGoogleCredential.recent
        render :index, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @credential.update(credential_params_for_update)
        if params[:connect_after_save].present?
          redirect_to connect_admin_google_credential_path(@credential), notice: "Google認証を保存しました。続けてGoogleと接続します。"
        else
          redirect_to admin_google_credentials_path, notice: "Google認証を更新しました"
        end
      else
        render :edit, status: :unprocessable_content
      end
    end

    def connect
      redirect_to admin_analytics_oauth_connect_path(google_credential_id: @credential.id)
    end

    private

    def set_credential
      @credential = AicooGoogleCredential.find(params.expect(:id))
    end

    def credential_params
      params.expect(aicoo_google_credential: %i[name google_cloud_project_id client_id client_secret refresh_token access_token token_expires_at google_account_email enabled notes])
    end

    def credential_params_for_update
      credential_params.tap do |permitted|
        permitted.delete(:client_id) if permitted[:client_id].blank?
        permitted.delete(:client_secret) if permitted[:client_secret].blank?
        permitted.delete(:refresh_token) if permitted[:refresh_token].blank?
        permitted.delete(:access_token) if permitted[:access_token].blank?
        permitted.delete(:token_expires_at) if permitted[:token_expires_at].blank?
        permitted.delete(:google_account_email) if permitted[:google_account_email].blank?
      end
    end
  end
end
