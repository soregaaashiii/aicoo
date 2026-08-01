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
    end

    test "connection test reports missing global authentication without an external request" do
      post test_admin_cloudflare_connection_url

      assert_redirected_to admin_cloudflare_connection_url
      assert_equal "Cloudflare接続テストに失敗しました: Cloudflare認証情報が未設定です。", flash[:alert]
    end
  end
end
