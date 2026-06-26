require "test_helper"

module Aicoo
  class AnalysisOrchestratorTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      AnalysisCandidate.delete_all
      DataSourceCostProfile.ensure_defaults!
      DataSourceCostProfile.find_by!(source_key: "serp").update!(
        average_cost_yen: 20,
        average_expected_profit_yen: 1_200,
        execution_mode: "manual",
        enabled: true
      )
    end

    test "generates analysis candidates by expected value and cost" do
      result = AnalysisOrchestrator.new(business: @business).call(limit: 5)

      assert_operator result.created_count, :>, 0
      assert_equal result.created_count, result.candidates.size
      candidate = result.candidates.find { |item| item.analysis_source == "serp" }
      assert candidate
      assert_equal "manual", candidate.execution_mode
      assert_operator candidate.expected_value_yen, :>, 0
      assert_operator candidate.roi.to_d, :>, 0
      assert_includes candidate.reason, "ROI"
    end

    test "does not generate disabled business data source" do
      BusinessDataSourceSetting.find_or_create_by!(business: @business, source_key: "serp").update!(
        enabled: false,
        connection_status: "linked"
      )

      result = AnalysisOrchestrator.new(business: @business).call

      assert_not result.candidates.any? { |candidate| candidate.analysis_source == "serp" }
    end

    test "updates existing candidate once per business source and day" do
      first = AnalysisOrchestrator.new(business: @business).call(limit: 3)
      second = AnalysisOrchestrator.new(business: @business).call(limit: 3)

      assert_operator first.created_count, :>, 0
      assert_equal 0, second.created_count
      assert_equal first.candidates.size, second.updated_count
      assert_equal first.candidates.size, AnalysisCandidate.where(business: @business, due_on: Date.current).count
    end
  end
end
