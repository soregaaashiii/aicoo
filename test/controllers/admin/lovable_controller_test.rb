require "test_helper"

module Admin
  class LovableControllerTest < ActionDispatch::IntegrationTest
    test "cloudflare pages settings can be stored without becoming a business data source" do
      get admin_lovable_url

      assert_response :success
      assert_select "#cloudflare-pages-settings"
      assert_select "input[name='cloudflare_pages[account_id]']"
      assert_select "input[name='cloudflare_pages[api_token]']"
      assert_select "input[name='cloudflare_pages[project_name]'][value='aicoo-lp']"

      patch admin_lovable_cloudflare_url, params: {
        cloudflare_pages: {
          account_id: "account-1",
          api_token: "secret-token",
          project_name: "aicoo-lp"
        }
      }

      assert_redirected_to admin_lovable_url(anchor: "cloudflare-pages-settings")
      profile = DataSourceCostProfile.find_by!(source_key: "cloudflare_pages")
      assert_equal "account-1", profile.credentials["account_id"]
      assert_equal "secret-token", profile.credentials["api_token"]
      assert_equal "aicoo-lp", profile.credentials["project_name"]
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
