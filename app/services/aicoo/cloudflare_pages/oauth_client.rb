require "json"
require "net/http"
require "securerandom"
require "uri"

module Aicoo
  module CloudflarePages
    class OauthClient
      class Error < StandardError; end

      Token = Data.define(:access_token, :refresh_token, :expires_at, :scope)
      AUTHORIZE_URL = "https://dash.cloudflare.com/oauth2/auth".freeze
      TOKEN_URL = "https://dash.cloudflare.com/oauth2/token".freeze

      def initialize(env: ENV, http_adapter: nil)
        @env = env
        @http_adapter = http_adapter || method(:perform_http)
      end

      def configured?
        client_id.present? && client_secret.present?
      end

      def authorization_url(state:, redirect_uri:)
        raise Error, "Cloudflare OAuth Clientが未設定です。" unless configured?

        query = {
          response_type: "code",
          client_id:,
          redirect_uri:,
          state:
        }
        query[:scope] = scopes if scopes.present?
        "#{AUTHORIZE_URL}?#{URI.encode_www_form(query)}"
      end

      def exchange!(code:, redirect_uri:)
        token_request(
          grant_type: "authorization_code",
          code:,
          redirect_uri:,
          client_id:,
          client_secret:
        )
      end

      def refresh!(refresh_token:)
        token_request(
          grant_type: "refresh_token",
          refresh_token:,
          client_id:,
          client_secret:
        )
      end

      private

      attr_reader :env, :http_adapter

      def client_id
        env["CLOUDFLARE_OAUTH_CLIENT_ID"].presence
      end

      def client_secret
        env["CLOUDFLARE_OAUTH_CLIENT_SECRET"].presence
      end

      def scopes
        env["CLOUDFLARE_OAUTH_SCOPES"].to_s.strip.presence
      end

      def token_request(parameters)
        uri = URI(TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(parameters)
        response = http_adapter.call(uri, request)
        payload = JSON.parse(response.body.presence || "{}")
        unless response.is_a?(Net::HTTPSuccess) && payload["access_token"].present?
          raise Error, payload["error_description"].presence || payload["error"].presence || "Cloudflare OAuth認証に失敗しました。"
        end

        Token.new(
          access_token: payload.fetch("access_token"),
          refresh_token: payload["refresh_token"],
          expires_at: payload["expires_in"].to_i.positive? ? Time.current + payload["expires_in"].to_i.seconds : nil,
          scope: payload["scope"]
        )
      rescue JSON::ParserError
        raise Error, "Cloudflare OAuthの応答を解析できませんでした。"
      end

      def perform_http(uri, request)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
          http.request(request)
        end
      end
    end
  end
end
