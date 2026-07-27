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
    assert_equal "lovable_handoff_ready", run.metadata["pipeline_status"]
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

  test "result repository waits for github webhook without a manual fetch button" do
    campaign = @business.business_campaigns.create!(name: "Webhook Campaign", campaign_type: "seo", status: "active")
    landing_page = @business.business_prototypes.create!(
      business_campaign: campaign,
      name: "Webhook LP",
      prototype_type: "github",
      location: "https://github.com/example/lovable-result",
      status: "active",
      metadata: {
        "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
        "lp_name" => "Webhook LP",
        "lp_public_status" => "testing",
        "ga4_page_path" => "/webhook-lp"
      }
    )
    run = AicooLabGenerationRun.create!(
      generation_type: "lp_generation",
      status: "succeeded",
      prompt: "Create LP",
      metadata: {
        "pipeline" => "lovable",
        "pipeline_status" => "github_webhook_waiting",
        "business_id" => @business.id,
        "landing_page_id" => 1,
        "landing_page_prototype_id" => landing_page.id,
        "version" => 1,
        "version_label" => "v1",
        "build_url" => "https://lovable.dev/?autosubmit=true#prompt=test",
        "lovable_result_repository" => "https://github.com/example/lovable-result",
        "lovable_result_branch" => "main",
        "publication" => {}
      }
    )
    landing_page.update!(metadata: landing_page.metadata.to_h.merge("lovable_generation_run_id" => run.id))

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)

    assert_response :success
    assert_includes response.body, "GitHub Push待ち"
    assert_includes response.body, "保存してGitHub Pushを待つ"
    assert_not_includes response.body, ">生成結果を取得<"
  end
end
