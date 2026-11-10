require "test_helper"

class BusinessServicesControllerTest < ActionDispatch::IntegrationTest
  test "creates business service from business page" do
    business = businesses(:suelog)

    assert_difference -> { BusinessService.count }, 1 do
      post business_business_services_url(business), params: {
        business_service: {
          name: "吸えログ本番",
          url: "https://suelog.jp",
          admin_url: "https://suelog.jp/admin",
          other_url: "https://status.suelog.jp",
          repository: "soregaaashiii/suelog",
          deploy_target: "Render",
          render_service: "suelog-web",
          stripe_account: "acct_test",
          domain: "suelog.jp",
          api_endpoint: "https://suelog.jp/api",
          status: "live"
        }
      }
    end

    assert_redirected_to business_url(business, anchor: "business-services")
    service = BusinessService.last
    assert_equal business, service.business
    assert_equal "live", service.status
    assert_equal "https://suelog.jp/admin", service.admin_url
    assert_equal "https://status.suelog.jp", service.other_url

    get business_url(business)
    assert_response :success
    assert_select "#business-service-access-card" do
      assert_select "a[href='https://suelog.jp']", text: "https://suelog.jp"
      assert_select "a[href='https://suelog.jp/admin']", text: "https://suelog.jp/admin"
      assert_select "a[href='https://status.suelog.jp']", text: "https://status.suelog.jp"
      assert_select "input[name^='business_service']", count: 0
    end
    assert_select "#business-services" do
      assert_select "input[name^='business_service']", count: 0
      assert_select "a[href='#{edit_business_path(business, anchor: "business-service-settings")}']", text: "設定"
    end
  end

  test "updates business service" do
    business = businesses(:suelog)
    service = business.business_services.create!(name: "MVP", status: "building")

    patch business_business_service_url(business, service), params: {
      business_service: {
        name: "MVP",
        status: "live",
        url: "https://mvp.example.com",
        admin_url: "https://mvp.example.com/admin",
        other_url: "https://docs.example.com/mvp"
      }
    }

    assert_redirected_to business_url(business, anchor: "business-services")
    assert_equal "live", service.reload.status
    assert_equal "https://mvp.example.com", service.url
    assert_equal "https://mvp.example.com/admin", service.admin_url
    assert_equal "https://docs.example.com/mvp", service.other_url
  end
end
