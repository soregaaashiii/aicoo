require "test_helper"

module Admin
  class SerpE2eChecksControllerTest < ActionDispatch::IntegrationTest
    test "shows serp e2e check with business selector" do
      get admin_serp_e2e_check_url(business_id: businesses(:suelog).id)

      assert_response :success
      assert_includes response.body, "SERP E2E診断"
      assert_includes response.body, "SERP Health"
      assert_includes response.body, "API"
      assert_includes response.body, "Keyword診断"
      assert_includes response.body, "Scan Plan"
      assert_includes response.body, "Action Candidate"
      assert_includes response.body, "Daily Run SERP Step"
    end

    test "repair approves pending keywords" do
      business = businesses(:suelog)
      keyword = business.business_serp_keywords.create!(keyword: "梅田 喫煙", source: "ai_suggested", status: "pending")

      post admin_serp_e2e_check_repair_url, params: {
        business_id: business.id,
        repair_action: "approve_pending_keywords"
      }

      assert_redirected_to admin_serp_e2e_check_url(business_id: business.id)
      assert_equal "active", keyword.reload.status
      assert_includes flash[:notice], "SERP E2E復旧を実行しました"
    end

    test "rejects unsafe repair action" do
      business = businesses(:suelog)

      post admin_serp_e2e_check_repair_url, params: {
        business_id: business.id,
        repair_action: "change_api_key"
      }

      assert_redirected_to admin_serp_e2e_check_url(business_id: business.id)
      assert_includes flash[:alert], "復旧できない操作"
    end
  end
end
