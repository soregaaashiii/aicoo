require "test_helper"

module Admin
  class GoogleCredentialsControllerTest < ActionDispatch::IntegrationTest
    test "shows google credentials index" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        google_cloud_project_id: "aicoo-500805",
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
      assert_includes response.body, "Record ID"
      assert_includes response.body, "##{credential.id}"
      assert_includes response.body, "現在使用中"
      assert_includes response.body, "owner@example.com"
      assert_includes response.body, "Project番号"
      assert_includes response.body, "aicoo-500805"
      assert_includes response.body, "client"
      assert_includes response.body, "保存済み"
      assert_includes response.body, "last_oauth_success_at"
      assert_includes response.body, "updated_at"
      assert_not_includes response.body, "client-secret-value"
      assert_not_includes response.body, "refresh-token-value"
      assert_not_includes response.body, "access-token-value"
    end

    test "creates google credential" do
      assert_difference("AicooGoogleCredential.count", 1) do
        post admin_google_credentials_url, params: {
          aicoo_google_credential: {
            name: "AICOO共通Google認証",
            google_cloud_project_id: "aicoo-500805",
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
      assert_equal "aicoo-500805", credential.google_cloud_project_id
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

    test "changing oauth client id invalidates old tokens and requires reauthentication" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        google_cloud_project_id: "old-project",
        client_id: "111-old.apps.googleusercontent.com",
        client_secret: "secret",
        refresh_token: "old-refresh",
        access_token: "old-access",
        token_expires_at: 1.hour.from_now,
        google_account_email: "owner@example.com",
        connected_at: Time.current
      )

      patch admin_google_credential_url(credential), params: {
        aicoo_google_credential: {
          name: "AICOO共通Google認証",
          google_cloud_project_id: "aicoo-500805",
          client_id: "222-new.apps.googleusercontent.com",
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
      assert_equal "222-new.apps.googleusercontent.com", credential.client_id
      assert_equal "aicoo-500805", credential.google_cloud_project_id
      assert_nil credential.refresh_token
      assert_nil credential.access_token
      assert_nil credential.token_expires_at
      assert_nil credential.google_account_email
      assert_nil credential.connected_at
      assert_predicate credential, :reauthentication_required?
    end

    test "changing oauth client secret invalidates old tokens" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "111-client.apps.googleusercontent.com",
        client_secret: "old-secret",
        refresh_token: "old-refresh",
        access_token: "old-access",
        connected_at: Time.current
      )

      patch admin_google_credential_url(credential), params: {
        aicoo_google_credential: {
          name: "AICOO共通Google認証",
          client_id: "",
          client_secret: "new-secret",
          refresh_token: "",
          access_token: "",
          token_expires_at: "",
          google_account_email: "",
          enabled: "1"
        }
      }

      credential.reload
      assert_equal "111-client.apps.googleusercontent.com", credential.client_id
      assert_equal "new-secret", credential.client_secret
      assert_nil credential.refresh_token
      assert_nil credential.access_token
      assert_nil credential.connected_at
    end

    test "updates credential and continues to google oauth" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        client_id: "old-client",
        client_secret: "old-secret",
        refresh_token: "old-refresh"
      )

      patch admin_google_credential_url(credential), params: {
        connect_after_save: "保存してGoogleと接続",
        aicoo_google_credential: {
          name: "AICOO共通Google認証",
          google_cloud_project_id: "aicoo-500805",
          client_id: "new-client",
          client_secret: "new-secret",
          refresh_token: "",
          access_token: "",
          token_expires_at: "",
          google_account_email: "",
          enabled: "1"
        }
      }

      credential.reload
      assert_equal "new-client", credential.client_id
      assert_equal "new-secret", credential.client_secret
      assert_equal "aicoo-500805", credential.google_cloud_project_id
      assert_nil credential.refresh_token
      assert_redirected_to connect_admin_google_credential_url(credential)
    end

    test "edit form shows saved client id so connect flow does not submit a blank old value" do
      credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        google_cloud_project_id: "aicoo-500805",
        client_id: "705900000000-new.apps.googleusercontent.com",
        client_secret: "secret"
      )

      get edit_admin_google_credential_url(credential)

      assert_response :success
      assert_includes response.body, "value=\"705900000000-new.apps.googleusercontent.com\""
      assert_includes response.body, "value=\"aicoo-500805\""
    end

    test "shows env mismatch warning and current google cloud project" do
      AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        google_cloud_project_id: "aicoo-500805",
        client_id: "222-new.apps.googleusercontent.com",
        client_secret: "secret",
        refresh_token: "refresh-token-value",
        connected_at: Time.current
      )

      with_env(
        "GOOGLE_CLIENT_ID" => "111-old.apps.googleusercontent.com",
        "GOOGLE_CLOUD_PROJECT" => "old-project"
      ) do
        get admin_google_credentials_url
      end

      assert_response :success
      assert_includes response.body, "aicoo-500805"
      assert_includes response.body, "222-new.apps.googleusercontent.com"
      assert_includes response.body, "ENVとDBのGoogle OAuth設定が異なります"
      assert_not_includes response.body, "再認証が必要です"
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

    private

    def with_env(values)
      previous = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
