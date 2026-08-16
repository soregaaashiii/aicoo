require "test_helper"

module Aicoo
  class OwnerDecisionSummaryTest < ActiveSupport::TestCase
    test "summarizes counts and rates" do
      candidate = action_candidates(:nagazakicho_article)
      candidate.update!(action_type: "seo_improvement", expected_total_value_yen: 10_000, confidence_score: 70)
      draft = CodexPromptDraft.from_action_candidate(candidate)
      draft.update!(risk_level: "low")

      OwnerDecisionLog.record!(
        subject: candidate,
        decision_type: "approve",
        decision_source: "action_candidate_detail",
        previous_status: "idea",
        new_status: "approved"
      )
      OwnerDecisionLog.record!(
        subject: draft,
        decision_type: "executed",
        decision_source: "codex_prompt_detail",
        previous_status: "copied",
        new_status: "executed"
      )

      summary = OwnerDecisionSummary.new.call

      assert_operator summary.today_count, :>=, 2
      assert_operator summary.last_7_days_count, :>=, 2
      assert_operator summary.counts_by_decision_type.fetch("approve"), :>=, 1
      assert summary.action_type_adoption_rates.any? { |rate| rate.label == "seo_improvement" }
      assert summary.risk_level_execution_rates.any? { |rate| rate.label == "low" }
      assert_not_empty summary.recent_logs
    end

    test "aggregates decision rates without one count per category" do
      query_count = count_owner_decision_log_queries do
        OwnerDecisionSummary.new.call
      end

      assert_operator query_count, :<=, 6
    end

    private

    def count_owner_decision_log_queries
      count = 0
      subscriber = lambda do |_name, _started, _finished, _id, payload|
        next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION]) || payload[:cached]
        next unless payload[:sql].to_s.match?(/\ASELECT/i)

        count += 1 if payload[:sql].include?('"owner_decision_logs"')
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
      count
    end
  end
end
