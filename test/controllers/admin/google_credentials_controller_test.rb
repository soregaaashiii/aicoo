require "test_helper"

module Admin
  class GoogleCredentialsControllerTest < ActionDispatch::IntegrationTest
    test "shows google credentials index" do
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "client-secret-value",
        refresh_token: "refresh-token-value",
        connected_at: Time.current
      )

      get admin_google_credentials_url

      assert_response :success
      assert_includes response.body, "Google認証一覧"
      assert_includes response.body, "接続済み"
      assert_includes response.body, "Googleと接続"
      assert_not_includes response.body, "client-secret-value"
      assert_not_includes response.body, "refresh-token-value"
    end

    test "creates google credential" do
      assert_difference("AicooGoogleCredential.count", 1) do
        post admin_google_credentials_url, params: {
          aicoo_google_credential: {
            name: "AICOO共通Google認証",
            client_id: "client",
            client_secret: "secret",
            refresh_token: "refresh",
            enabled: "1"
          }
        }
      end

      credential = AicooGoogleCredential.last
      assert_redirected_to admin_google_credentials_url
      assert_equal "client", credential.client_id
      assert_equal "secret", credential.client_secret
      assert_equal "refresh", credential.refresh_token
    end

    test "blank update does not clear saved secrets" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh"
      )

      patch admin_google_credential_url(credential), params: {
        aicoo_google_credential: {
          name: "AICOO共通Google認証 Updated",
          client_id: "",
          client_secret: "",
          refresh_token: "",
          enabled: "1"
        }
      }

      credential.reload
      assert_redirected_to admin_google_credentials_url
      assert_equal "AICOO共通Google認証 Updated", credential.name
      assert_equal "client", credential.client_id
      assert_equal "secret", credential.client_secret
      assert_equal "refresh", credential.refresh_token
    end
  end
end
