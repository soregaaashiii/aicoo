require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "dashboard page redirects to Today" do
    get dashboard_url

    assert_redirected_to owner_focus_url
  end

  test "owner dashboard alias redirects to Home" do
    get "/owner/dashboard"

    assert_redirected_to owner_dashboard_url
  end
end
