require "test_helper"

module Admin
  class IdeaPipelineControllerTest < ActionDispatch::IntegrationTest
    test "index shows pipeline and generate action" do
      get admin_idea_pipeline_index_url

      assert_response :success
      assert_includes response.body, "Idea Pipeline"
      assert_includes response.body, "Ideaを生成"
      assert_includes response.body, "Idea"
      assert_includes response.body, "MVP"
    end

    test "generate creates ideas" do
      assert_difference("IdeaPipelineItem.count", 3) do
        post generate_admin_idea_pipeline_index_url, params: { count: 3 }
      end

      assert_redirected_to admin_idea_pipeline_index_url
    end

    test "show displays pipeline detail and mvp spec area" do
      item = create_item
      item.update!(status: "scored", final_score: 80)

      get admin_idea_pipeline_url(item)

      assert_response :success
      assert_includes response.body, item.title
      assert_includes response.body, "Stage操作"
      assert_includes response.body, "SERP結果評価"
      assert_includes response.body, "SERP状態"
      assert_includes response.body, "未実行"
      assert_includes response.body, "SERPなしでLP生成"
      assert_includes response.body, "MVP仕様書"
    end

    test "score action updates item" do
      item = create_item

      post score_admin_idea_pipeline_url(item)

      assert_redirected_to admin_idea_pipeline_url(item)
      assert_equal "scored", item.reload.status
    end

    test "generate lp works without serp when scored" do
      item = create_item
      item.update!(status: "scored", final_score: 80)

      assert_difference("AicooLabLandingPage.count", 1) do
        post generate_lp_admin_idea_pipeline_url(item)
      end

      assert_redirected_to admin_idea_pipeline_url(item)
      assert_equal "lp_generated", item.reload.status
      assert_equal false, item.metadata.dig("lp_generation", "serp_used")
    end

    test "generate lp rejects unsafe item" do
      item = create_item
      item.update!(status: "unsafe", final_score: 90)

      assert_no_difference("AicooLabLandingPage.count") do
        post generate_lp_admin_idea_pipeline_url(item)
      end

      assert_redirected_to admin_idea_pipeline_url(item)
      assert_equal "unsafe", item.reload.status
    end

    private

    def create_item
      IdeaPipelineItem.create!(
        title: "テストIdea",
        short_description: "テスト説明",
        problem: "課題",
        target_user: "ユーザー",
        revenue_model: "問い合わせ",
        mvp_concept: "LPで検証",
        lp_concept: "LP案",
        difficulty_score: 20,
        development_hours: 4,
        ai_implementation_score: 80
      )
    end
  end
end
