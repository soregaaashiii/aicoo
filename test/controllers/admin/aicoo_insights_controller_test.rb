require "test_helper"

module Admin
  class AicooInsightsControllerTest < ActionDispatch::IntegrationTest
    test "shows insights dashboard" do
      action = businesses(:suelog).action_candidates.create!(
        title: "Insight controller action",
        action_type: "seo_improvement",
        generation_source: "ai_insight",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        evaluation_reason: "CTR改善: controller"
      )
      AicooInsightGenerationRun.create!(
        started_at: Time.current,
        finished_at: Time.current,
        source: "manual",
        status: "success",
        generated_count: 1,
        skipped_count: 2
      )

      get admin_aicoo_insights_url

      assert_response :success
      assert_includes response.body, "改善案"
      assert_includes response.body, "検出された改善機会"
      assert_includes response.body, action.title
      assert_includes response.body, "改善案を生成"
      assert_includes response.body, "生成履歴"
      assert_includes response.body, "manual"
      assert_includes response.body, "success"
    end

    test "generates insights from admin action" do
      business = Business.create!(name: "Insight controller generate")
      AicooDataSnapshot.create!(
        source_type: "gsc",
        source_id: business.id,
        payload: {
          "business_id" => business.id,
          "rows" => [
            { "query" => "天王寺 喫煙", "impressions" => 250, "clicks" => 1, "ctr" => 0.004, "position" => 4 }
          ]
        }
      )

      assert_difference("ActionCandidate.where(generation_source: 'ai_insight').count", 1) do
        assert_difference("AicooInsightGenerationRun.count", 1) do
          post admin_aicoo_insights_generate_url
        end
      end

      assert_redirected_to admin_aicoo_insights_url
      assert_match(/改善案を1件生成しました/, flash[:notice])
      assert_equal "manual", AicooInsightGenerationRun.last.source
    end
  end
end
