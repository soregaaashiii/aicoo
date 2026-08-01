require "test_helper"

module Admin
  class LovableControllerTest < ActionDispatch::IntegrationTest
    test "cloudflare authentication is managed only from global settings" do
      get admin_lovable_url

      assert_response :success
      assert_select "#cloudflare-pages-settings", count: 0
      assert_select "input[name='cloudflare_pages[account_id]']", count: 0
      assert_select "input[name='cloudflare_pages[api_token]']", count: 0

      patch admin_lovable_cloudflare_url

      assert_redirected_to admin_cloudflare_connection_url
      assert_not_includes DataSourceCostProfile.ordered.pluck(:source_key), "cloudflare_pages"
      assert_not_includes Aicoo::BusinessRegistrationAnalyzer::DATA_SOURCE_KEYS, "cloudflare_pages"
    end

    test "github webhook settings expose url diagnostics and store the shared secret" do
      get admin_lovable_url

      assert_response :success
      assert_select "#github-webhook-settings"
      assert_select "code", text: /\/webhooks\/github/
      assert_select "input[name='github_webhook[secret]']"

      patch admin_lovable_github_webhook_url, params: {
        github_webhook: { secret: "shared-webhook-secret" }
      }

      assert_redirected_to admin_lovable_url(anchor: "github-webhook-settings")
      profile = DataSourceCostProfile.find_by!(source_key: "github_lovable_webhook")
      assert_equal "shared-webhook-secret", profile.credentials["secret"]
      assert_not_includes DataSourceCostProfile.ordered.pluck(:source_key), "github_lovable_webhook"
    end
  end
end
