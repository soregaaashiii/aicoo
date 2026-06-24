require "test_helper"

module Aicoo
  class DiscoverySourcePerformanceReportTest < ActiveSupport::TestCase
    setup do
      OpportunityDiscoveryItem.delete_all
      ActionResult.delete_all
      ActionExecution.delete_all
    end

    test "aggregates source performance and funnel" do
      create_source_result(source_type: "owner_discovery", predicted: 10_000, actual: 8_000)
      create_source_result(source_type: "owner_discovery", predicted: 10_000, actual: 12_000)
      create_source_result(source_type: "trend", predicted: 10_000, actual: 0)
      create_source_result(source_type: "trend", predicted: 10_000, actual: -1_000)

      report = DiscoverySourcePerformanceReport.new.call
      owner_summary = report.source_summaries.find { |summary| summary.source_type == "owner_discovery" }
      trend_summary = report.source_summaries.find { |summary| summary.source_type == "trend" }

      assert_equal 2, owner_summary.opportunities_count
      assert_equal 2, owner_summary.candidates_count
      assert_equal 2, owner_summary.executions_count
      assert_equal 2, owner_summary.results_count
      assert_equal 20_000, owner_summary.total_actual_profit
      assert_equal 1.to_d, owner_summary.overall_success_rate
      assert_equal 1.to_d, owner_summary.opportunity_to_candidate_rate
      assert_equal "owner_discovery", report.strongest_sources.first.source_type
      assert_equal "trend", report.weakest_sources.first.source_type
      assert_includes report.warnings, "trend の成功率が低下しています。"
      assert trend_summary.total_actual_profit.negative?
    end

    test "keeps empty sources in funnel" do
      report = DiscoverySourcePerformanceReport.new.call

      assert report.conversion_funnel.any? { |item| item.source_type == "gsc" }
      assert_equal 0, report.conversion_funnel.find { |item| item.source_type == "gsc" }.opportunities_count
    end

    private

    def create_source_result(source_type:, predicted:, actual:)
      opportunity = OpportunityDiscoveryItem.create!(
        title: "#{source_type} opportunity #{SecureRandom.hex(4)}",
        source_type:,
        business: businesses(:suelog)
      )
      candidate = opportunity.convert_to_action_candidate!
      candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        completed_at: Time.current,
        result_summary: "done"
      )
      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        predicted_expected_profit_yen: predicted,
        predicted_success_probability: 0.8,
        actual_profit_yen: actual,
        actual_revenue_yen: actual
      )
    end
  end
end
