require "test_helper"

module Aicoo
  class StrategicLearningReportTest < ActiveSupport::TestCase
    test "summarizes philosophy and decision patterns" do
      AicooSetting.current.update!(
        long_term_profit_weight: 55,
        short_term_profit_weight: 20,
        learning_weight: 15,
        automation_weight: 5,
        exploration_weight: 5
      )
      OwnerDecisionLog.create!(
        subject_type: "ActionCandidate",
        subject_id: 10_001,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        title: "Approved SEO",
        action_type: "seo_improvement",
        risk_level: "low",
        generation_source: "manual",
        expected_value_yen: 20_000,
        decided_at: Time.current,
        metadata: { "strategic_learning" => { "strategic_score" => "80", "decision_log_coefficient" => "1.1" } }
      )
      OwnerDecisionLog.create!(
        subject_type: "ActionCandidate",
        subject_id: 10_002,
        decision_type: "skip",
        decision_source: "owner_tasks",
        title: "Skipped high value",
        action_type: "seo_improvement",
        risk_level: "medium",
        expected_value_yen: 80_000,
        decided_at: Time.current,
        metadata: { "strategic_learning" => { "strategic_score" => "85", "decision_log_coefficient" => "0.9" } }
      )

      report = StrategicLearningReport.new.call

      assert_equal 55, report.philosophy_weights.fetch(:long_term_profit_weight)
      assert_operator report.decision_correction_rate, :>, 0
      assert_operator report.contrary_decision_count, :>=, 1
      assert_equal "seo_improvement", report.top_approved_action_types.first.first
      assert_not_empty report.high_value_skipped_logs
      assert_not_empty report.decision_coefficients
      assert report.guardrail_settings.fetch(:enabled)
      assert report.guardrail_settings.key?(:max_boost_rate)
      assert_operator report.guardrail_warning_30_days_count, :>=, 0
      assert_operator report.weakened_decision_log_count, :>=, 0
    end
  end
end
