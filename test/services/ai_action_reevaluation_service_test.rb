require "test_helper"

class AiActionReevaluationServiceTest < ActiveSupport::TestCase
  test "updates evaluation fields and stores the evaluation run" do
    action_candidate = action_candidates(:nagazakicho_article)
    service = AiActionReevaluationService.new(action_candidate, client: FakeClient.new)

    assert_difference -> { AiEvaluationRun.count }, 1 do
      result = service.call

      assert_equal action_candidate, result.action_candidate
      assert_equal 80_000, action_candidate.reload.immediate_value_yen
      assert_equal 0.75.to_d, action_candidate.success_probability
      assert_equal 90, action_candidate.strategic_value_score
      assert_equal 88, action_candidate.data_confidence_score
      assert_equal "ai_reevaluation", action_candidate.generation_source
      assert_equal "Updated reason", action_candidate.evaluation_reason
    end
  end

  class FakeClient
    attr_reader :model

    def initialize
      @model = "test-model"
    end

    def create_json(prompt:, schema_name:, schema:)
      {
        parsed: {
          "action" => {
            "title" => "ignored",
            "description" => "ignored",
            "action_type" => "seo_article",
            "immediate_value_yen" => 80_000,
            "success_probability" => 0.75,
            "strategic_value_score" => 90,
            "risk_reduction_score" => 50,
            "confidence_score" => 85,
            "data_confidence_score" => 88,
            "expected_hours" => 2,
            "cost_yen" => 0,
            "evaluation_reason" => "Updated reason",
            "execution_prompt" => "Updated prompt"
          }
        },
        raw_response: JSON.generate({ ok: true, prompt:, schema_name:, schema: }),
        model:
      }
    end
  end
end
