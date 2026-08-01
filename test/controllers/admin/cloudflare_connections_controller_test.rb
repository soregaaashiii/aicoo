require "test_helper"

module Admin
  class CloudflareConnectionsControllerTest < ActionDispatch::IntegrationTest
    test "shows the global cloudflare connection screen without business credentials" do
      get admin_cloudflare_connection_url

      assert_response :success
      assert_select "input[name='cloudflare_connection[account_id]']"
      assert_select "input[name='cloudflare_connection[api_token]']"
      assert_select "input[name*='business']", count: 0
      assert_select "form[action='#{test_admin_cloudflare_connection_path}']", count: 0
      assert_select "[data-cloudflare-connection-control][data-cloudflare-connection-state='disconnected']"
      assert_select "button[data-cloudflare-connection-reveal]", text: "Cloudflareへ接続", count: 1 do |buttons|
        assert_nil buttons.first["disabled"]
        assert_nil buttons.first["aria-busy"]
        assert_not_includes buttons.first["class"].to_s.split, "is-submitting"
      end
      assert_select "[data-cloudflare-connection-error].is-hidden", count: 1
    end

    test "shows connected state without rendering the connection action as loading" do
      DataSourceCostProfile.create!(
        source_key: "cloudflare_pages",
        name: "Cloudflare Pages",
        execution_mode: "auto",
        enabled: true,
        metadata: {
          "credentials" => { "account_id" => "account-1", "api_token" => "token-1" },
          "cloudflare" => { "status" => "connected", "use_stored_credentials" => true }
        }
      )

      get admin_cloudflare_connection_url

      assert_response :success
      assert_select "[data-cloudflare-connected-label]", text: "接続済み", count: 1
      assert_select "[data-cloudflare-connected-label][aria-busy]", count: 0
      assert_select "[data-cloudflare-connected-label].is-submitting", count: 0
      assert_select "form[data-cloudflare-connection-submit][action='#{test_admin_cloudflare_connection_path}']", count: 1
    end

    test "shows an actionable error state without leaving the connect button loading" do
      DataSourceCostProfile.create!(
        source_key: "cloudflare_pages",
        name: "Cloudflare Pages",
        execution_mode: "auto",
        enabled: true,
        last_error: "token expired",
        metadata: {
          "credentials" => { "account_id" => "account-1", "api_token" => "bad-token" },
          "cloudflare" => { "status" => "error", "use_stored_credentials" => true, "last_error" => "token expired" }
        }
      )

      get admin_cloudflare_connection_url

      assert_response :success
      assert_select "[data-cloudflare-connection-control][data-cloudflare-connection-state='error']"
      assert_select "[data-cloudflare-connected-label]", count: 0
      assert_select "button[data-cloudflare-connection-reveal]", text: "Cloudflareへ接続", count: 1 do |buttons|
        assert_nil buttons.first["disabled"]
        assert_nil buttons.first["aria-busy"]
      end
      assert_select ".aicoo-lab-help.status-critical:not(.is-hidden) p", text: /token expired/
    end

    test "connection feedback resets loading for turbo restore failure and timeout" do
      get admin_cloudflare_connection_url

      assert_response :success
      assert_includes response.body, "turbo:before-cache"
      assert_includes response.body, "turbo:submit-end"
      assert_includes response.body, "turbo:fetch-request-error"
      assert_includes response.body, "pageshow"
      assert_includes response.body, "Cloudflare接続がタイムアウトしました。接続状態を確認して再試行してください。"
      assert_includes response.body, "Cloudflareへ接続できませんでした。通信状態を確認して再試行してください。"
    end

    test "connection test reports missing global authentication without an external request" do
      post test_admin_cloudflare_connection_url

      assert_redirected_to admin_cloudflare_connection_url
      assert_equal "Cloudflare接続テストに失敗しました: Cloudflare認証情報が未設定です。", flash[:alert]
    end
  end
end
