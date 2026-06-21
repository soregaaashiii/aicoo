require "json"
require "net/http"

module AicooAnalytics
  class GoogleOauthAuthorization
    AUTH_ENDPOINT = URI("https://accounts.google.com/o/oauth2/v2/auth")
    TOKEN_ENDPOINT = URI("https://oauth2.googleapis.com/token")
    SCOPES = [
      "https://www.googleapis.com/auth/webmasters.readonly",
      "https://www.googleapis.com/auth/analytics.readonly"
    ].freeze

    TokenResponse = Data.define(:access_token, :refresh_token)

    class Error < StandardError; end
    class MissingCredentialsError < Error; end

    def self.authorization_uri(client_id:, redirect_uri:, state: nil)
      query = {
        client_id:,
        redirect_uri:,
        response_type: "code",
        scope: SCOPES.join(" "),
        access_type: "offline",
        prompt: "consent",
        include_granted_scopes: "true"
      }
      query[:state] = state if state.present?

      uri = AUTH_ENDPOINT.dup
      uri.query = URI.encode_www_form(query)
      uri
    end

    def self.exchange_code(code:, client_id:, client_secret:, redirect_uri:)
      validate_credentials!(client_id:, client_secret:)

      response = Net::HTTP.post_form(
        TOKEN_ENDPOINT,
        code:,
        client_id:,
        client_secret:,
        redirect_uri:,
        grant_type: "authorization_code"
      )

      raise Error, friendly_error_message(response.body, response.code) unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body)
      TokenResponse.new(
        access_token: parsed["access_token"],
        refresh_token: parsed["refresh_token"]
      )
    rescue JSON::ParserError => e
      raise Error, "Google OAuthレスポンスを解析できませんでした: #{e.message}"
    end

    def self.validate_credentials!(client_id:, client_secret:)
      missing = []
      missing << "GOOGLE_CLIENT_IDまたは保存済みclient_id" if client_id.blank?
      missing << "GOOGLE_CLIENT_SECRETまたは保存済みclient_secret" if client_secret.blank?
      return if missing.empty?

      raise MissingCredentialsError, "#{missing.join(' / ')} が未設定です。"
    end

    def self.friendly_error_message(body, code)
      parsed = JSON.parse(body.presence || "{}")
      error = parsed["error"].presence || "unknown_error"
      description = parsed["error_description"].presence
      hint = case error
      when "invalid_grant"
        "認証コードが期限切れ、またはredirect_uriが一致していない可能性があります。もう一度Googleと接続してください。"
      when "unauthorized_client"
        "OAuthクライアントの種類・Client ID/Secret・承認済みリダイレクトURIを確認してください。"
      when "invalid_scope"
        "GSC/GA4のscopeが許可されているか確認してください。"
      else
        "Google OAuth設定を確認してください。"
      end

      [ "Google OAuth token exchange failed: #{code} #{error}", description, hint ].compact.join(" ")
    rescue JSON::ParserError
      "Google OAuth token exchange failed: #{code} #{body}"
    end

    private_class_method :validate_credentials!, :friendly_error_message
  end
end
