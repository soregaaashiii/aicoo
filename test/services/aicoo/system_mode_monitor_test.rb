require "test_helper"

module Aicoo
  class SystemModeMonitorTest < ActiveSupport::TestCase
    test "returns system health, pipeline, queues, learning, executor, and charts" do
      monitor = SystemModeMonitor.new.call

      assert monitor.system_health_score
      assert_includes %w[healthy attention warning critical], monitor.system_health_status
      assert monitor.status_cards.any? { |card| card.label == "Daily Run" }
      assert monitor.pipeline_steps.any? { |step| step.label == "ActionCandidate" }
      assert monitor.queue_cards.any? { |card| card.label == "Execution Queue" }
      assert monitor.learning_cards.any? { |card| card.label == "Strategic Learning" }
      assert monitor.executor_cards.any? { |card| card.label == "Ready" }
      assert monitor.setting_cards.any? { |card| card.label == "Retry" }
      assert monitor.charts.any? { |chart| chart.title == "Prediction Accuracy" }
      assert monitor.charts.any? { |chart| chart.title == "Health Trend" }
    end

    test "pipeline reports recent records" do
      ActionCandidate.create!(
        business: businesses(:suelog),
        title: "System monitor candidate",
        status: "idea",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 1,
        expected_hours: 1
      )

      step = SystemModeMonitor.new.call.pipeline_steps.find { |item| item.key == "action_candidate" }

      assert_operator step.count, :>=, 1
      assert_equal "healthy", step.status
    end
  end
end
