require "test_helper"

class PublicBusinessServicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = Business.create!(
      name: "MVPサービステスト",
      description: "小さく使えるSaaSの土台",
      status: "exploring",
      lifecycle_stage: "lp_validation",
      resource_status: "active",
      business_type: "landing_page",
      source: "serp",
      created_by_aicoo: true
    )
    @service = @business.business_services.create!(
      name: "MVPサービステスト SaaS",
      status: "building",
      deploy_target: "aicoo_mvp_service",
      url: "/mvp/pending",
      metadata: { "service_kind" => "saas_mvp_foundation" }
    )
    @service.update!(url: public_business_service_path(@service))
  end

  test "shows mvp service foundation separate from landing page" do
    get public_business_service_url(@service)

    assert_response :success
    assert_includes response.body, @service.name
    assert_includes response.body, "MVP Service"
    assert_includes response.body, "事前登録"
  end

  test "records signup activity for mvp service" do
    assert_difference -> { @business.business_activity_logs.where(activity_type: "mvp_signup").count }, 1 do
      post public_business_service_signup_url(@service),
           params: {
             service_signup: {
               email: "owner@example.com",
               note: "最小機能を試したい"
             }
           }
    end

    assert_response :success
    activity = @business.business_activity_logs.where(activity_type: "mvp_signup").last
    assert_equal "BusinessService", activity.resource_type
    assert_equal @service.id.to_s, activity.resource_id
    assert_equal "owner@example.com", activity.metadata["email"]
  end
end
