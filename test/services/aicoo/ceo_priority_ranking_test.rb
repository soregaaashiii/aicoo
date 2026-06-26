require "test_helper"

module Aicoo
  class CeoPriorityRankingTest < ActiveSupport::TestCase
    include Rails.application.routes.url_helpers

    test "sorts by recommended score by default" do
      high_score = create_ranked_candidate!("High recommendation", final_score: 90_000, expected_profit: 10_000, hourly: 10_000, learning: 1_000)
      low_score = create_ranked_candidate!("Low recommendation", final_score: 1_000, expected_profit: 100_000, hourly: 100_000, learning: 20_000)

      result = CeoPriorityRanking.new(tasks: [ task_for(low_score), task_for(high_score) ]).call

      assert_equal "High recommendation", result.items.first.action_candidate.title
    end

    test "sorts by revenue hourly and learning value" do
      revenue = create_ranked_candidate!("Revenue leader", final_score: 10_000, expected_profit: 120_000, hourly: 20_000, learning: 1_000)
      hourly = create_ranked_candidate!("Hourly leader", final_score: 20_000, expected_profit: 40_000, hourly: 200_000, learning: 5_000)
      learning = create_ranked_candidate!("Learning leader", final_score: 30_000, expected_profit: 30_000, hourly: 30_000, learning: 80_000)
      tasks = [ task_for(hourly), task_for(learning), task_for(revenue) ]

      revenue_result = CeoPriorityRanking.new(tasks:, sort_mode: "revenue").call
      hourly_result = CeoPriorityRanking.new(tasks:, sort_mode: "hourly").call
      learning_result = CeoPriorityRanking.new(tasks:, sort_mode: "learning").call

      assert_equal "Revenue leader", revenue_result.items.first.action_candidate.title
      assert_equal "Hourly leader", hourly_result.items.first.action_candidate.title
      assert_equal "Learning leader", learning_result.items.first.action_candidate.title
    end

    test "adds owner facing recommendation reasons and success probability" do
      candidate = create_ranked_candidate!("Evidence backed candidate", final_score: 80_000, expected_profit: 50_000, hourly: 50_000, learning: 20_000)
      candidate.update_column(:metadata, candidate.metadata.merge("evidence" => { "score" => 80, "summary" => [ "表示回数が増えています" ] }))

      item = CeoPriorityRanking.new(tasks: [ task_for(candidate.reload) ]).call.items.first

      assert_includes item.recommendation_reasons, "収益性が高い"
      assert_includes item.recommendation_reasons, "根拠データが揃っています"
      assert_equal 0.8.to_d, item.success_probability
    end

    private

    def create_ranked_candidate!(title, final_score:, expected_profit:, hourly:, learning:)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title:,
        status: "approved",
        action_type: "seo_improvement",
        expected_profit_yen: expected_profit,
        immediate_value_yen: expected_profit,
        success_probability: 0.8,
        expected_hours: 1
      )
      candidate.update_columns(
        final_score:,
        final_expected_value_yen: expected_profit,
        expected_hourly_value_yen: hourly,
        expected_learning_value_yen: learning,
        practicality_score: 80
      )
      candidate.create_action_execution!(status: "ready", execution_type: "manual")
      candidate
    end

    def task_for(candidate)
      OwnerTaskInbox::Task.new(
        priority: "medium",
        task_type: "action_execution_ready",
        title: "#{candidate.title} を実行開始",
        description: "実行準備が完了しています。",
        target_label: candidate.business.name,
        target_path: action_execution_path(candidate.action_execution),
        reason: "期待利益 #{candidate.expected_profit_yen.to_i}円",
        created_at: Time.current,
        quick_actions: [
          OwnerTaskInbox::QuickAction.new(
            label: "実行開始",
            method: :patch,
            path: start_action_execution_path(candidate.action_execution),
            confirm_message: nil,
            style: "primary"
          )
        ]
      )
    end
  end
end
