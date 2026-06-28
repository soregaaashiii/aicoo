module Admin
  class GoogleCredentialsController < ApplicationController
    before_action :set_credential, only: %i[edit update connect]

    def index
      @credentials = AicooGoogleCredential.recent.to_a.each(&:reload)
      @current_credential = AicooGoogleCredential.default&.reload
      log_google_credential_display_event!
      @credential = AicooGoogleCredential.new(name: "AICOO共通Google認証", enabled: true)
    end

    def new
      @credential = AicooGoogleCredential.new(name: "AICOO共通Google認証", enabled: true)
    end

    def create
      @credential = AicooGoogleCredential.new(credential_params)
      log_google_credential_save_event!("create_params_received", @credential, credential_params)
      if @credential.save
        @credential.reload
        log_google_credential_save_event!("create_saved", @credential)
        if params[:connect_after_save].present?
          log_google_credential_save_event!("create_connect_redirect", @credential, target_path: connect_admin_google_credential_path(@credential))
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
      log_google_credential_save_event!("update_params_received", @credential, credential_params_for_update)
      if @credential.update(credential_params_for_update)
        @credential.reload
        log_google_credential_save_event!("update_saved", @credential)
        if params[:connect_after_save].present?
          log_google_credential_save_event!("update_connect_redirect", @credential, target_path: connect_admin_google_credential_path(@credential))
          redirect_to connect_admin_google_credential_path(@credential), notice: "Google認証を保存しました。続けてGoogleと接続します。"
        else
          redirect_to admin_google_credentials_path, notice: "Google認証を更新しました"
        end
      else
        render :edit, status: :unprocessable_content
      end
    end

    def connect
      @credential.reload
      log_google_credential_save_event!("connect_action", @credential, target_path: admin_analytics_oauth_connect_path(google_credential_id: @credential.id))
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

    def log_google_credential_save_event!(event, credential, extra = {})
      Rails.logger.info(
        "Google Credential #{event} " \
        "#{{
          credential_id: credential.id,
          persisted: credential.persisted?,
          client_id: credential.client_id,
          project_id: credential.google_cloud_project_id,
          project_number: credential.oauth_project_number,
          refresh_token_present: credential.refresh_token.present?,
          last_oauth_success_at: credential.last_oauth_success_at
        }.merge(sanitized_log_extra(extra)).compact.to_json}"
      )
    end

    def log_google_credential_display_event!
      Rails.logger.info(
        "Google Credential display " \
        "#{{
          current_credential_id: @current_credential&.id,
          list_credential_ids: @credentials.map(&:id),
          current_client_id: @current_credential&.client_id,
          current_project_id: @current_credential&.google_cloud_project_id,
          current_refresh_token_present: @current_credential&.refresh_token.present?
        }.compact.to_json}"
      )
    end

    def sanitized_log_extra(extra)
      if extra.respond_to?(:to_unsafe_h)
        return { params: sanitized_log_params(extra.to_unsafe_h) }
      end
      if extra.is_a?(Hash) && extra.keys.any? { |key| key.to_s.in?(%w[client_id client_secret google_cloud_project_id refresh_token access_token]) }
        return { params: sanitized_log_params(extra) }
      end

      extra.to_h.transform_values do |value|
        if value.respond_to?(:to_unsafe_h)
          { params: sanitized_log_params(value.to_unsafe_h) }
        elsif value.is_a?(Hash)
          { params: sanitized_log_params(value) }
        else
          value
        end
      end
    end

    def sanitized_log_params(raw_params)
      raw_params.to_h.transform_values.with_index do |value, _index|
        value
      end.except("client_secret", "refresh_token", "access_token")
    end
  end
end
