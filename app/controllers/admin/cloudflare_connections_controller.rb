module Admin
  class CloudflareConnectionsController < ApplicationController
    def show
      load_connection
    end

    def update
      values = params.expect(cloudflare_connection: %i[account_id api_token])
      connection_manager.connect_with_api_token!(
        account_id: values[:account_id],
        api_token: values[:api_token]
      )
      redirect_to admin_cloudflare_connection_path, notice: "Cloudflareへ接続しました。"
    rescue ActiveRecord::RecordInvalid, Aicoo::CloudflarePages::ApiClient::Error => e
      redirect_to admin_cloudflare_connection_path, alert: "Cloudflareへ接続できませんでした: #{e.message}"
    end

    def connect
      oauth = oauth_client
      unless oauth.configured?
        redirect_to admin_cloudflare_connection_path, alert: "Cloudflare OAuth Clientが未設定です。API Tokenで接続してください。"
        return
      end

      state = SecureRandom.hex(32)
      session[:cloudflare_oauth_state] = state
      redirect_to oauth.authorization_url(
        state:,
        redirect_uri: callback_admin_cloudflare_connection_url
      ), allow_other_host: true
    rescue Aicoo::CloudflarePages::OauthClient::Error => e
      redirect_to admin_cloudflare_connection_path, alert: e.message
    end

    def callback
      expected_state = session.delete(:cloudflare_oauth_state).to_s
      unless expected_state.present? && secure_state_match?(params[:state], expected_state)
        redirect_to admin_cloudflare_connection_path, alert: "Cloudflare OAuthのstateを確認できませんでした。"
        return
      end
      if params[:error].present?
        redirect_to admin_cloudflare_connection_path, alert: "Cloudflare接続が許可されませんでした: #{params[:error_description].presence || params[:error]}"
        return
      end

      token = oauth_client.exchange!(
        code: params.expect(:code),
        redirect_uri: callback_admin_cloudflare_connection_url
      )
      connection_manager.connect_with_oauth!(token:)
      redirect_to admin_cloudflare_connection_path, notice: "Cloudflareへ接続しました。"
    rescue ActiveRecord::RecordInvalid, Aicoo::CloudflarePages::ApiClient::Error, Aicoo::CloudflarePages::OauthClient::Error => e
      redirect_to admin_cloudflare_connection_path, alert: "Cloudflare OAuth接続に失敗しました: #{e.message}"
    end

    def test
      connection_manager.test!
      redirect_to admin_cloudflare_connection_path, notice: "Cloudflare接続テストに成功しました。Pages Projectを更新しました。"
    rescue ActiveRecord::RecordInvalid, Aicoo::CloudflarePages::ApiClient::Error => e
      redirect_to admin_cloudflare_connection_path, alert: "Cloudflare接続テストに失敗しました: #{e.message}"
    end

    def create_project
      values = params.expect(cloudflare_project: %i[name production_branch])
      connection_manager.create_project!(
        name: values[:name].to_s.strip,
        production_branch: values[:production_branch].presence || "main"
      )
      redirect_to admin_cloudflare_connection_path, notice: "Cloudflare Pages Projectを作成しました。"
    rescue ActiveRecord::RecordInvalid, Aicoo::CloudflarePages::ApiClient::Error => e
      redirect_to admin_cloudflare_connection_path, alert: "Pages Projectを作成できませんでした: #{e.message}"
    end

    private

    def load_connection
      @cloudflare_connection_manager = connection_manager
      @cloudflare_configuration = connection_manager.configuration
      @cloudflare_oauth_available = connection_manager.oauth_available?
      @cloudflare_projects = @cloudflare_configuration.available_projects
    end

    def connection_manager
      @connection_manager ||= Aicoo::CloudflarePages::ConnectionManager.new
    end

    def oauth_client
      @oauth_client ||= Aicoo::CloudflarePages::OauthClient.new
    end

    def secure_state_match?(actual, expected)
      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(actual.to_s),
        Digest::SHA256.hexdigest(expected.to_s)
      )
    end
  end
end
