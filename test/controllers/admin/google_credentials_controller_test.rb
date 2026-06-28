require "test_helper"

module Admin
  class GoogleCredentialsControllerTest < ActionDispatch::IntegrationTest
    test "shows google credentials index" do
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "client",
        client_secret: "client-secret-value",
        refresh_token: "refresh-token-value",
        access_token: "access-token-value",
        token_expires_at: 1.hour.from_now,
        google_account_email: "owner@example.com",
        connected_at: Time.current
      )

      get admin_google_credentials_url

      assert_response :success
      assert_includes response.body, "Google認証一覧"
      assert_includes response.body, "接続済み"
      assert_includes response.body, "Googleと接続"
      assert_includes response.body, "owner@example.com"
      assert_includes response.body, "Project番号"
      assert_includes response.body, "client"
      assert_includes response.body, "保存済み"
      assert_not_includes response.body, "client-secret-value"
      assert_not_includes response.body, "refresh-token-value"
      assert_not_includes response.body, "access-token-value"
    end

    test "creates google credential" do
      assert_difference("AicooGoogleCredential.count", 1) do
        post admin_google_credentials_url, params: {
          aicoo_google_credential: {
            name: "AICOO共通Google認証",
            client_id: "client",
            client_secret: "secret",
            refresh_token: "refresh",
            access_token: "access",
            google_account_email: "owner@example.com",
            enabled: "1"
          }
        }
      end

      credential = AicooGoogleCredential.last
      assert_redirected_to admin_google_credentials_url
      assert_equal "client", credential.client_id
      assert_equal "secret", credential.client_secret
      assert_equal "refresh", credential.refresh_token
      assert_equal "access", credential.access_token
      assert_equal "owner@example.com", credential.google_account_email
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
          access_token: "",
          token_expires_at: "",
          google_account_email: "",
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

    test "can save credential and continue to google oauth" do
      post admin_google_credentials_url, params: {
        connect_after_save: "保存してGoogleと接続",
        aicoo_google_credential: {
          name: "AICOO共通Google認証",
          client_id: "client",
          client_secret: "secret",
          enabled: "1"
        }
      }

      credential = AicooGoogleCredential.last
      assert_redirected_to connect_admin_google_credential_url(credential)
    end
  end
end
