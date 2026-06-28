require "test_helper"

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
    assert_includes response.body, "今日"
    assert_includes response.body, "確認タスク"
    assert_includes response.body, "発見と検証"
    assert_includes response.body, "現在位置"
  end

  test "system mode uses monitor sidebar and breadcrumb" do
    get dashboard_url

    assert_response :success
    assert_includes response.body, "AICOO"
    assert_includes response.body, "SYSTEM MODE"
    assert_includes response.body, "Daily Monitor"
    assert_includes response.body, "Deep Diagnostics"
    assert_includes response.body, "Pipeline"
    assert_includes response.body, "Jobs"
    assert_includes response.body, "Queues"
    assert_includes response.body, "現在位置"
  end

  test "business pages keep the same system shell" do
    get business_url(businesses(:suelog))

    assert_response :success
    assert_includes response.body, "SYSTEM MODE"
    assert_includes response.body, "Business"
    assert_includes response.body, "Integrations"
    assert_includes response.body, "現在位置"
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
end
