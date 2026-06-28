require "test_helper"
require "base64"

class AicooManagementAccessTest < ActionDispatch::IntegrationTest
  test "management screens require basic auth when protection is enabled" do
    with_basic_auth_env do
      [
        dashboard_url,
        businesses_url,
        action_candidates_url,
        action_results_url,
        judge_url,
        aicoo_daily_runs_url,
        admin_aicoo_revenue_url,
        admin_aicoo_executor_url,
        admin_aicoo_datahub_url,
        aicoo_setting_url
      ].each do |protected_url|
        get protected_url
        assert_response :unauthorized, "#{protected_url} should require Basic auth"

        get protected_url, headers: basic_auth_headers("aicoo-admin", "secret-password")
        assert_response :success, "#{protected_url} should be available with Basic auth"
      end
    end
  end

  test "management screens are forbidden when credentials are missing" do
    with_env(
      "AICOO_ENABLE_BASIC_AUTH" => "true",
      "AICOO_BASIC_AUTH_USERNAME" => nil,
      "AICOO_BASIC_AUTH_PASSWORD" => nil
    ) do
      get dashboard_url

      assert_response :forbidden
      assert_includes response.body, "AICOO management access is not configured."
    end
  end

  test "published landing page stays public when management protection is enabled" do
    landing_page = create_published_landing_page

    with_basic_auth_env do
      get aicoo_lab_published_lp_url(landing_page.published_slug)

      assert_response :success
      assert_includes response.body, "Public LP headline"

      get public_landing_pages_url
      assert_response :success

      get public_lp_url(landing_page.published_slug)
      assert_response :success
      assert_includes response.body, "Public LP headline"
    end
  end

  test "published landing page interactions stay public when management protection is enabled" do
    landing_page = create_published_landing_page

    with_basic_auth_env do
      assert_difference("AicooLabLandingPageEvent.where(event_type: 'cta_click').count", 1) do
        post aicoo_lab_published_lp_cta_click_url(landing_page.published_slug)
      end
      assert_redirected_to aicoo_lab_published_lp_signup_path(landing_page.published_slug)

      get aicoo_lab_published_lp_signup_url(landing_page.published_slug)
      assert_response :success

      assert_difference("AicooLabSignup.count", 1) do
        post aicoo_lab_published_lp_signup_url(landing_page.published_slug), params: {
          aicoo_lab_signup: { email: "public@example.com", note: "外部公開テスト" }
        }
      end
      assert_response :success
    end
  end

  test "preview landing pages are not public when management protection is enabled" do
    landing_page = create_published_landing_page

    with_basic_auth_env do
      get aicoo_lab_preview_url(landing_page.preview_slug)

      assert_response :unauthorized
    end
  end

  test "unused action mailbox internal routes are blocked" do
    with_basic_auth_env do
      [
        "/rails/action_mailbox/postmark/inbound_emails",
        "/rails/action_mailbox/relay/inbound_emails",
        "/rails/conductor/action_mailbox/inbound_emails",
        "/rails/conductor/action_mailbox/inbound_emails/new"
      ].each do |blocked_path|
        get blocked_path
        assert_response :not_found, "#{blocked_path} should be closed"
      end
    end
  end

  private

  def create_published_landing_page
    experiment = AicooLabExperiment.create!(
      title: "Public LP access",
      experiment_type: "lp",
      acquisition_channel: "sns",
      approval_status: "approved"
    )
    experiment.create_aicoo_lab_landing_page!(
      headline: "Public LP headline",
      subheadline: "Public LP subheadline",
      body: "Public LP body",
      cta_text: "事前登録する",
      status: "published",
      public_status: "published",
      published_at: Time.current,
      published_slug: "public-lp-access"
    )
  end

  def with_basic_auth_env(&)
    with_env(
      "AICOO_ENABLE_BASIC_AUTH" => "true",
      "AICOO_BASIC_AUTH_USERNAME" => "aicoo-admin",
      "AICOO_BASIC_AUTH_PASSWORD" => "secret-password",
      &
    )
  end

  def with_env(values)
    originals = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    originals.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def basic_auth_headers(username, password)
    encoded = Base64.strict_encode64("#{username}:#{password}")
    { "Authorization" => "Basic #{encoded}" }
  end
end
