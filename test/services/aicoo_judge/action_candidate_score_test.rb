require "test_helper"

module AicooJudge
  class ActionCandidateScoreTest < ActiveSupport::TestCase
    test "calculates judge adjusted score from generation source and action type accuracy" do
      create_result(generation_source: "ai_business", action_type: "seo_improvement", actual: 10_000)
      candidate = create_candidate(generation_source: "ai_business", action_type: "seo_improvement")

      score = ActionCandidateScore.new.score_for(candidate)

      assert_equal candidate.final_score.to_d, score.judge_adjusted_score
      assert_equal 1.to_d, score.generation_source_accuracy
      assert_equal 1.to_d, score.action_type_accuracy
    end

    test "clamps weak judge correction to lower bound" do
      create_result(generation_source: "manual", action_type: "ui_improvement", actual: -10_000)
      candidate = create_candidate(generation_source: "manual", action_type: "ui_improvement")

      score = ActionCandidateScore.new.score_for(candidate)

      assert_equal 0.5.to_d, score.multiplier
      assert_equal candidate.final_score.to_d * 0.5, score.judge_adjusted_score
    end

    test "uses neutral multiplier when accuracy data is missing" do
      candidate = create_candidate(generation_source: "ai_cross_business", action_type: "sales")

      score = ActionCandidateScore.new.score_for(candidate)

      assert_nil score.generation_source_accuracy
      assert_nil score.action_type_accuracy
      assert_equal 1.to_d, score.multiplier
    end

    private

    def create_candidate(generation_source:, action_type:)
      ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Score candidate #{SecureRandom.hex(4)}",
        action_type:,
        generation_source:,
        immediate_value_yen: 10_000,
        success_probability: 1,
        expected_hours: 1
      )
    end

    def create_result(generation_source:, action_type:, actual:)
      candidate = create_candidate(generation_source:, action_type:)
      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current - 10,
        evaluated_on: Date.current,
        actual_profit_yen: actual,
        evaluation_status: "evaluated"
      )
    end
  end
end
