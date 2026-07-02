require "test_helper"

module Admin
  class IntegratedDecisionsControllerTest < ActionDispatch::IntegrationTest
    test "shows new business top list first" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "新規事業候補: 警備AI",
        description: "警備AIのLP検証",
        action_type: "build_lp",
        department: "new_business",
        generation_source: "integrated_decision",
        status: "idea",
        immediate_value_yen: 80_000,
        success_probability: 0.25,
        expected_hours: 2,
        metadata: {
          "candidate_kind" => "new_business",
          "source_query" => "警備 AI",
          "target_customer" => "警備会社",
          "revenue_model" => "SaaS",
          "validation_step" => "LPを公開して問い合わせを見る"
        }
      )

      get admin_integrated_decision_url

      assert_response :success
      assert_includes response.body, "開始すべき新規事業 TOP10"
      assert_includes response.body, candidate.title
      assert_includes response.body, "警備会社"
      assert_includes response.body, "LP検証へ進める"
      assert_operator response.body.index("開始すべき新規事業 TOP10"), :<, response.body.index("Integrated Summary")
    end
  end
end
