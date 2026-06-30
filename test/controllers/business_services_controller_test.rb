require "test_helper"

class BusinessServicesControllerTest < ActionDispatch::IntegrationTest
  test "creates business service from business page" do
    business = businesses(:suelog)

    assert_difference -> { BusinessService.count }, 1 do
      post business_business_services_url(business), params: {
        business_service: {
          name: "吸えログ本番",
          url: "https://suelog.jp",
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
  end

  test "updates business service" do
    business = businesses(:suelog)
    service = business.business_services.create!(name: "MVP", status: "building")

    patch business_business_service_url(business, service), params: {
      business_service: {
        name: "MVP",
        status: "live",
        url: "https://mvp.example.com"
      }
    }

    assert_redirected_to business_url(business, anchor: "business-services")
    assert_equal "live", service.reload.status
    assert_equal "https://mvp.example.com", service.url
  end
end
