require "test_helper"
require "base64"

class AicooManagementAccessTest < ActionDispatch::IntegrationTest
  test "management screens require basic auth when protection is enabled" do
    with_basic_auth_env do
      get dashboard_url
      assert_response :unauthorized

      get dashboard_url, headers: basic_auth_headers("aicoo-admin", "secret-password")
      assert_response :success
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
