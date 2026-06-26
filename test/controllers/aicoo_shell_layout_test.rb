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
    assert_includes response.body, "Today"
    assert_includes response.body, "Tasks"
    assert_includes response.body, "Opportunities"
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
end
