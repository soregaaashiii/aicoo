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
    assert_includes response.body, "Lovableで作成"
    assert_includes response.body, "Promptを見る"
  end

  test "creates an official Build URL version regardless of MCP configuration" do
    assert_difference("AicooLabGenerationRun.count", 1) do
      post business_lovable_landing_page_url(@business)
    end

    run = AicooLabGenerationRun.last
    assert_redirected_to run.metadata["build_url"]
    assert_equal "lovable_handoff_required", run.metadata["pipeline_status"]
    assert_equal "build_with_url", run.metadata["launcher"]
  end

  test "prepares an editable prompt without generating a Build URL" do
    assert_difference("AicooLabGenerationRun.count", 1) do
      post prepare_business_lovable_landing_page_url(@business)
    end

    run = AicooLabGenerationRun.last
    assert_redirected_to business_lovable_landing_page_path(@business, anchor: "lovable-prompt")
    assert_equal "draft", run.status
    assert_equal "prompt_ready", run.metadata["pipeline_status"]
    assert_nil run.metadata["build_url"]

    patch update_prompt_version_business_lovable_landing_page_url(@business, generation_run_id: run.id), params: { prompt: "Edited prompt" }
    assert_redirected_to business_lovable_landing_page_path(@business, anchor: "lovable-prompt")
    assert_equal "Edited prompt", run.reload.prompt
  end

  test "business detail exposes Lovable LP actions" do
    get business_url(@business)

    assert_response :success
    assert_includes response.body, "Lovableで作成"
    assert_includes response.body, "Promptを見る"
    assert_includes response.body, business_lovable_landing_page_path(@business)
  end
end
