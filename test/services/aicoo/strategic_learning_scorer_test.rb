require "test_helper"

module Aicoo
  class StrategicLearningScorerTest < ActiveSupport::TestCase
    test "uses strategic philosophy before decision log coefficient" do
      AicooSetting.current.update!(
        long_term_profit_weight: 0,
        short_term_profit_weight: 0,
        learning_weight: 100,
        automation_weight: 0,
        exploration_weight: 0
      )
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "学習データを増やす",
        action_type: "data_preparation",
        immediate_value_yen: 1_000,
        success_probability: 0.5,
        expected_learning_value_yen: 80_000
      )

      result = StrategicLearningScorer.new(candidate, base_score: 100).call

      assert_operator result.strategic_score, :>, 50
      assert_equal 1.to_d, result.decision_log_coefficient
      assert_operator result.final_score, :>, 100
    end

    test "applies decision log coefficient as bounded correction" do
      AicooSetting.current.update!(strategic_learning_decision_log_min_count: 3)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "SEO改善を行う",
        action_type: "seo_improvement",
        generation_source: "manual",
        immediate_value_yen: 10_000,
        success_probability: 0.5
      )

      3.times do |index|
        OwnerDecisionLog.create!(
          subject_type: "ActionCandidate",
          subject_id: candidate.id + index + 1000,
          decision_type: "approve",
          decision_source: "action_candidate_detail",
          title: "Approved #{index}",
          action_type: "seo_improvement",
          decided_at: Time.current
        )
      end

      result = StrategicLearningScorer.new(candidate, base_score: 100).call

      assert_operator result.decision_log_coefficient, :>, 1
      assert_operator result.decision_log_coefficient, :<=, 1.25
    end

    test "does not boost beyond max boost rate" do
      AicooSetting.current.update!(
        strategic_learning_max_boost_rate: 0.10,
        strategic_learning_warning_threshold_rate: 0.05,
        strategic_learning_decision_log_min_count: 0,
        learning_weight: 100,
        long_term_profit_weight: 0,
        short_term_profit_weight: 0,
        automation_weight: 0,
        exploration_weight: 0
      )
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "学習価値が高い",
        action_type: "data_preparation",
        expected_learning_value_yen: 100_000
      )

      result = StrategicLearningScorer.new(candidate, base_score: 100).call

      assert_equal 110.to_d, result.final_score
      assert_equal 0.1.to_d, result.guardrail.fetch("adjustment_rate").to_d
      assert result.guardrail.fetch("warning")
    end

    test "does not penalize beyond max penalty rate" do
      AicooSetting.current.update!(
        strategic_learning_max_penalty_rate: 0.10,
        strategic_learning_decision_log_min_count: 3
      )
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "Rejectされがちな施策",
        action_type: "sales"
      )
      3.times do |index|
        OwnerDecisionLog.create!(
          subject_type: "ActionCandidate",
          subject_id: 20_000 + index,
          decision_type: "reject",
          decision_source: "action_candidate_detail",
          action_type: "sales",
          decided_at: Time.current
        )
      end

      result = StrategicLearningScorer.new(candidate, base_score: 100).call

      assert_equal 90.to_d, result.final_score
      assert_equal(-0.1.to_d, result.guardrail.fetch("adjustment_rate").to_d)
    end

    test "weakens decision correction when decision logs are insufficient" do
      AicooSetting.current.update!(strategic_learning_decision_log_min_count: 10)
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "少数ログの施策",
        action_type: "market_research"
      )
      3.times do |index|
        OwnerDecisionLog.create!(
          subject_type: "ActionCandidate",
          subject_id: 30_000 + index,
          decision_type: "approve",
          decision_source: "action_candidate_detail",
          action_type: "market_research",
          decided_at: Time.current
        )
      end

      result = StrategicLearningScorer.new(candidate, base_score: 100).call

      assert_operator result.decision_log_coefficient, :<, result.guardrail.fetch("raw_decision_log_coefficient").to_d
      assert_includes result.guardrail.fetch("warning_reason"), "Decision Log件数が少ない"
    end

    test "weakens high risk boost" do
      AicooSetting.current.update!(
        strategic_learning_max_boost_rate: 0.50,
        learning_weight: 100,
        long_term_profit_weight: 0,
        short_term_profit_weight: 0,
        automation_weight: 0,
        exploration_weight: 0
      )
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "high risk学習施策",
        action_type: "data_preparation",
        expected_learning_value_yen: 100_000,
        metadata: { "risk_level" => "high" }
      )

      result = StrategicLearningScorer.new(candidate, base_score: 100).call

      assert_operator result.final_score, :<, 150.to_d
      assert_includes result.guardrail.fetch("warning_reason"), "high risk"
    end
  end
end
