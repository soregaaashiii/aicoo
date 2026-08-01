require "test_helper"

module Aicoo
  module CloudflarePages
    class OauthClientTest < ActiveSupport::TestCase
      test "builds authorization url and exchanges the code" do
        env = {
          "CLOUDFLARE_OAUTH_CLIENT_ID" => "client-id",
          "CLOUDFLARE_OAUTH_CLIENT_SECRET" => "client-secret",
          "CLOUDFLARE_OAUTH_SCOPES" => "pages:read pages:write"
        }
        adapter = lambda do |_uri, request|
          assert_includes request.body, "grant_type=authorization_code"
          assert_includes request.body, "code=code-1"
          response(
            access_token: "access-token",
            refresh_token: "refresh-token",
            expires_in: 3_600,
            scope: "pages:read pages:write"
          )
        end
        client = OauthClient.new(env:, http_adapter: adapter)

        url = URI(client.authorization_url(state: "state-1", redirect_uri: "https://aicoo.example/callback"))
        query = Rack::Utils.parse_nested_query(url.query)
        assert_equal "client-id", query["client_id"]
        assert_equal "state-1", query["state"]
        assert_equal "pages:read pages:write", query["scope"]

        token = client.exchange!(code: "code-1", redirect_uri: "https://aicoo.example/callback")
        assert_equal "access-token", token.access_token
        assert_equal "refresh-token", token.refresh_token
        assert token.expires_at.future?
      end

      private

      def response(body)
        Net::HTTPOK.new("1.1", "200", "response").tap do |result|
          result.define_singleton_method(:body) { JSON.generate(body) }
        end
      end
    end
  end
end
