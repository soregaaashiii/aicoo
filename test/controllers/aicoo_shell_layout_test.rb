require "test_helper"
require "base64"

class AicooShellLayoutTest < ActionDispatch::IntegrationTest
  test "ceo mode uses unified header sidebar and breadcrumb" do
    get owner_focus_url

    assert_response :success
    assert_includes response.body, "AICOO"
    assert_includes response.body, "CEO MODE"
    assert_includes response.body, "SYSTEM MODE"
    assert_includes response.body, "Search"
    assert_includes response.body, "Notifications"
    assert_includes response.body, "Profile"
    assert_includes response.body, "目的から探す"
    assert_includes response.body, "事業"
    assert_includes response.body, "事業ごとの状態"
    assert_includes response.body, "今日やること"
    assert_includes response.body, "AI活動"
    assert_includes response.body, "新規事業 / Lab"
    assert_includes response.body, "学習"
    assert_includes response.body, "分析"
    assert_includes response.body, "設定"
    assert_includes response.body, "現在位置"
  end

  test "system mode uses purpose sidebar and breadcrumb" do
    get dashboard_url

    assert_response :success
    assert_includes response.body, "AICOO"
    assert_includes response.body, "SYSTEM MODE"
    assert_includes response.body, "事業"
    assert_includes response.body, "AI活動"
    assert_includes response.body, "新規事業 / Lab"
    assert_includes response.body, "学習"
    assert_includes response.body, "分析"
    assert_includes response.body, "設定"
    assert_includes response.body, "状態を見る"
    assert_includes response.body, "現在位置"
  end

  test "business pages keep the same system shell" do
    get business_url(businesses(:suelog))

    assert_response :success
    assert_includes response.body, "SYSTEM MODE"
    assert_includes response.body, "事業"
    assert_includes response.body, "事業一覧"
    assert_includes response.body, "Google連携"
    assert_includes response.body, "現在位置"
  end

  test "business scoped detail pages keep business context" do
    action_candidate = action_candidates(:nagazakicho_article)

    get action_candidate_url(action_candidate)

    assert_response :success
    assert_select ".aicoo-sidebar-group.active .aicoo-sidebar-category strong", text: "事業"
    assert_select ".purpose-context-bar", text: /改善案/
    assert_includes response.body, "この事業へ戻る"
  end

  test "business revenue detail pages keep business context" do
    revenue_event = RevenueEvent.create!(
      business: businesses(:suelog),
      occurred_on: Date.current,
      event_type: "revenue",
      amount: 500
    )

    get revenue_event_url(revenue_event)

    assert_response :success
    assert_select ".aicoo-sidebar-group.active .aicoo-sidebar-category strong", text: "事業"
    assert_select ".purpose-context-bar", text: /売上/
    assert_includes response.body, "この事業へ戻る"
  end

  test "ga4 tag is not rendered in test environment" do
    previous = ENV.fetch("GA4_MEASUREMENT_ID", nil)
    ENV["GA4_MEASUREMENT_ID"] = "G-E5KCHJTFVP"

    get owner_focus_url

    assert_response :success
    assert_not_includes response.body, "googletagmanager.com/gtag/js"
    assert_not_includes response.body, "G-E5KCHJTFVP"
  ensure
    previous.nil? ? ENV.delete("GA4_MEASUREMENT_ID") : ENV["GA4_MEASUREMENT_ID"] = previous
  end

  test "ga4 tag is not rendered on management layout even in production" do
    with_env_values(
      "GA4_MEASUREMENT_ID" => "G-E5KCHJTFVP",
      "AICOO_BASIC_AUTH_USERNAME" => "aicoo-admin",
      "AICOO_BASIC_AUTH_PASSWORD" => "secret-password"
    ) do
      with_rails_env("production") do
        get owner_focus_url, headers: basic_auth_headers("aicoo-admin", "secret-password")
      end
    end

    assert_response :success
    assert_not_includes response.body, "googletagmanager.com/gtag/js"
    assert_not_includes response.body, "G-E5KCHJTFVP"
    assert_not_includes response.body, "gtag('event', 'page_view'"
  end

  test "google site verification is not rendered in test environment" do
    previous = ENV.fetch("GOOGLE_SITE_VERIFICATION", nil)
    ENV["GOOGLE_SITE_VERIFICATION"] = "google-token"

    get owner_focus_url

    assert_response :success
    assert_not_includes response.body, "google-site-verification"
    assert_not_includes response.body, "google-token"
  ensure
    previous.nil? ? ENV.delete("GOOGLE_SITE_VERIFICATION") : ENV["GOOGLE_SITE_VERIFICATION"] = previous
  end

  private

  def basic_auth_headers(username, password)
    credentials = Base64.strict_encode64("#{username}:#{password}")
    { "HTTP_AUTHORIZATION" => "Basic #{credentials}" }
  end

  def with_env_values(values)
    originals = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_rails_env(name)
    original = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new(name) }
    yield
  ensure
    Rails.define_singleton_method(:env) { original.call }
  end
end
