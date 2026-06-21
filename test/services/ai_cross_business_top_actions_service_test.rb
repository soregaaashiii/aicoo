require "test_helper"

class AiCrossBusinessTopActionsServiceTest < ActiveSupport::TestCase
  test "creates cross-business action candidates and stores runs per business" do
    service = AiCrossBusinessTopActionsService.new(client: FakeClient.new(business_ids: [ businesses(:suelog).id, businesses(:cards).id ]))

    assert_difference -> { ActionCandidate.count }, 2 do
      assert_difference -> { AiEvaluationRun.count }, 2 do
        result = service.call

        assert_equal 2, result.action_candidates.size
        assert_equal [ businesses(:cards).id, businesses(:suelog).id ].sort, result.action_candidates.map(&:business_id).sort
        assert_equal 2, result.runs.size
        assert result.action_candidates.all? { |action| action.title.include?("具体アクション") }
        assert result.action_candidates.all? { |action| action.generation_source == "ai_cross_business" }
      end
    end
  end

  class FakeClient
    attr_reader :model

    def initialize(business_ids:)
      @model = "test-model"
      @business_ids = business_ids
    end

    def create_json(prompt:, schema_name:, schema:)
      {
        parsed: {
          "actions" => [
            action_payload(@business_ids.first, "吸えログで梅田喫煙居酒屋記事の内部リンクを改善する"),
            action_payload(@business_ids.second, "名刺共有アプリで管理者権限UIを改善する")
          ]
        },
        raw_response: JSON.generate({ ok: true, prompt:, schema_name:, schema: }),
        model:
      }
    end

    private

    def action_payload(business_id, title)
      {
        "business_id" => business_id,
        "title" => "#{title} 具体アクション",
        "description" => "Cross business generated action",
        "action_type" => "seo_improvement",
        "immediate_value_yen" => 20_000,
        "success_probability" => 0.5,
        "strategic_value_score" => 70,
        "risk_reduction_score" => 50,
        "confidence_score" => 60,
        "data_confidence_score" => 75,
        "expected_hours" => 2,
        "cost_yen" => 0,
        "evaluation_reason" => "Cross-business priority reason",
        "execution_prompt" => "Execute the concrete action"
      }
    end
  end
end
