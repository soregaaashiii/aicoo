require "test_helper"

class AiActionGeneratorServiceTest < ActiveSupport::TestCase
  test "creates action candidates and stores the evaluation run" do
    business = businesses(:suelog)
    service = AiActionGeneratorService.new(business, client: FakeClient.new(actions: 5))

    assert_difference -> { ActionCandidate.count }, 5 do
      assert_difference -> { AiEvaluationRun.count }, 1 do
        result = service.call

        assert_equal 5, result.action_candidates.size
        assert_equal 5, result.run.created_action_count
        assert_equal "test-model", stored_model_name(result.run)
        assert_equal "ai_business", result.action_candidates.first.generation_source
        assert_equal 80, result.action_candidates.first.data_confidence_score
      end
    end
  end

  test "skips forbidden actions returned by ai for business type" do
    business = businesses(:suelog)
    service = AiActionGeneratorService.new(business, client: FakeClient.new(actions: 3, action_type: "build_lp"))

    assert_no_difference -> { ActionCandidate.count } do
      result = service.call

      assert_empty result.action_candidates
      assert_equal 0, result.run.created_action_count
    end
  end

  private

  def stored_model_name(run)
    AiEvaluationRun.connection.select_value("SELECT model_name FROM ai_evaluation_runs WHERE id = #{run.id.to_i}")
  end

  class FakeClient
    attr_reader :model

    def initialize(actions:, action_type: "market_research")
      @actions = actions
      @action_type = action_type
      @model = "test-model"
    end

    def create_json(prompt:, schema_name:, schema:)
      {
        parsed: {
          "actions" => Array.new(@actions) { |index| action_payload(index) }
        },
        raw_response: JSON.generate({ ok: true, prompt:, schema_name:, schema: }),
        model:
      }
    end

    private

    def action_payload(index)
      {
        "title" => "AI action #{index}",
        "description" => "Generated action",
        "action_type" => @action_type,
        "immediate_value_yen" => 10_000,
        "success_probability" => 0.5,
        "strategic_value_score" => 60,
        "risk_reduction_score" => 40,
        "confidence_score" => 70,
        "data_confidence_score" => 80,
        "expected_hours" => 2,
        "cost_yen" => 0,
        "evaluation_reason" => "Good test reason",
        "execution_prompt" => "Do the test action"
      }
    end
  end
end
