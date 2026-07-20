require "test_helper"

class LovableLandingPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:suelog)
  end

  test "shows the LP Studio with the separated workflow" do
    get business_lovable_landing_page_url(@business)

    assert_response :success
    assert_includes response.body, "LP Studio"
    assert_includes response.body, "AICOO要件"
    assert_includes response.body, "Lovable Preview"
    assert_includes response.body, "Codex公開"
    assert_includes response.body, "LP作成を開始"
  end

  test "creates a Build URL version when MCP is not configured" do
    original_token = ENV.delete("LOVABLE_MCP_ACCESS_TOKEN")
    original_access_token = ENV.delete("LOVABLE_ACCESS_TOKEN")

    assert_difference("AicooLabGenerationRun.count", 1) do
      post business_lovable_landing_page_url(@business)
    end

    assert_redirected_to business_lovable_landing_page_path(@business)
    assert_equal "lovable_handoff_required", AicooLabGenerationRun.last.metadata["pipeline_status"]
  ensure
    ENV["LOVABLE_MCP_ACCESS_TOKEN"] = original_token if original_token
    ENV["LOVABLE_ACCESS_TOKEN"] = original_access_token if original_access_token
  end

  test "business detail exposes Lovable LP actions" do
    get business_url(@business)

    assert_response :success
    assert_includes response.body, "LP作成"
    assert_includes response.body, business_lovable_landing_page_path(@business)
  end
end
