require "test_helper"

module Admin
  class PipelineE2eChecksControllerTest < ActionDispatch::IntegrationTest
    setup do
      DataSourceCostProfile.find_or_create_by!(source_key: "serp") do |profile|
        profile.name = "SERP"
        profile.execution_mode = "manual"
      end.update!(api_key: "serper-key")
    end

    test "shows e2e check page" do
      item = create_pipeline_item_with_lp
      run = Aicoo::PipelineEngine.new(item).call

      get admin_pipeline_e2e_check_url(pipeline_run_id: run.id)

      assert_response :success
      assert_includes response.body, "Pipeline E2Eチェック"
      assert_includes response.body, "Idea承認"
      assert_includes response.body, "Business作成"
      assert_includes response.body, "Business一覧表示"
      assert_includes response.body, "LP生成"
      assert_includes response.body, "sitemap反映"
      assert_includes response.body, "Auto Revision Queue"
      assert_includes response.body, "自動改修ループE2E"
      assert_includes response.body, "ActionCandidate生成"
      assert_includes response.body, "Codex Prompt生成"
      assert_includes response.body, "Owner承認待ち"
      assert_includes response.body, "実行後Activity / ActionResult"
    end

    test "repair button creates business and links landing page" do
      item = create_pipeline_item_with_lp
      landing_page = item.aicoo_lab_landing_page
      run = Aicoo::PipelineEngine.new(item).call

      assert_difference("Business.count", 1) do
        post admin_pipeline_e2e_check_repair_url,
             params: { pipeline_run_id: run.id, repair_action: "create_business" }
      end

      assert_redirected_to admin_pipeline_e2e_check_url(pipeline_run_id: run.id)
      assert item.reload.business
      assert_equal item.business, landing_page.reload.business
    end

    private

    def create_pipeline_item_with_lp
      item = IdeaPipelineItem.create!(
        title: "E2E Controller Idea",
        short_description: "Business未作成のLP",
        problem: "紐付けがない",
        target_user: "Owner",
        revenue_model: "送客",
        mvp_concept: "LP",
        lp_concept: "LP",
        difficulty_score: 20,
        development_hours: 4,
        ai_implementation_score: 80,
        status: "owner_approved",
        final_score: 75,
        evaluated_at: 1.hour.ago
      )
      landing_page = Aicoo::IdeaPipeline::LandingPageBuilder.new(item).call
      landing_page.update!(
        status: "published",
        public_status: "published",
        published_at: Time.current,
        published_slug: "controller-e2e-check"
      )
      item.update!(business: nil)
      item.reload
    end
  end
end
