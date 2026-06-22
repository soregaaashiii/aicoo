require "test_helper"

module AicooMetaEvaluator
  class MetaEvaluatorTest < ActiveSupport::TestCase
    test "gsc confidence grows with impressions and clicks" do
      business = businesses(:suelog)
      business.business_metric_dailies.create!(
        recorded_on: Date.current,
        impressions: 5_000,
        clicks: 150
      )
      candidate = build_candidate(business:)

      result = GscEvaluator.new(candidate).call

      assert_equal "gsc", result.evaluator_type
      assert_operator result.confidence_score, :>=, 90
      assert_operator result.expected_value_yen, :>=, 0
    end

    test "judge confidence is low with few action results and high with many" do
      business = businesses(:suelog)
      candidate = create_candidate(business:, action_type: "seo_improvement")
      2.times { create_action_result(business:, action_type: "seo_improvement", actual_profit_yen: 1_000) }

      low_result = JudgeEvaluator.new(candidate).call
      assert_equal 2, low_result.metadata.fetch(:evaluated_count)
      assert_operator low_result.confidence_score, :<=, 10

      98.times { create_action_result(business:, action_type: "seo_improvement", actual_profit_yen: 1_000) }
      high_result = JudgeEvaluator.new(candidate.reload).call

      assert_equal 100, high_result.metadata.fetch(:evaluated_count)
      assert_operator high_result.confidence_score, :>=, 95
    end

    test "revenue confidence is zero without revenue events and high with many events" do
      business = businesses(:suelog)
      candidate = build_candidate(business:)

      empty_result = RevenueEvaluator.new(candidate).call
      assert_equal 0, empty_result.confidence_score

      50.times do |index|
        business.revenue_events.create!(occurred_on: Date.current - index.days, event_type: "revenue", amount: 1_000)
      end

      high_result = RevenueEvaluator.new(candidate).call
      assert_operator high_result.confidence_score, :>=, 95
      assert_operator high_result.expected_value_yen, :>, 0
    end

    test "meta evaluator gives low confidence evaluator less influence" do
      business = businesses(:suelog)
      candidate = build_candidate(business:)
      high = EvaluationResult.new(
        evaluator_type: "gsc",
        expected_value_yen: 10_000,
        confidence_score: 90,
        reason: "high confidence",
        metadata: {}
      )
      low = EvaluationResult.new(
        evaluator_type: "judge",
        expected_value_yen: 100_000,
        confidence_score: 10,
        reason: "low confidence",
        metadata: {}
      )

      result = with_evaluators([ high, low ]) { MetaEvaluator.new(candidate).call }

      assert_in_delta 19_000, result.final_expected_value_yen, 1
      assert_operator result.final_confidence_score, :>, 80
    end

    test "action candidate stores final expected value confidence and evaluator breakdown" do
      business = businesses(:suelog)
      business.business_metric_dailies.create!(recorded_on: Date.current, impressions: 1_000, clicks: 10)

      candidate = create_candidate(business:)

      assert_operator candidate.final_expected_value_yen, :>=, 0
      assert_operator candidate.final_confidence_score, :>=, 0
      assert_equal %w[gsc ga4 judge revenue learning], candidate.metadata.fetch("evaluator_breakdown").map { |entry| entry["evaluator_type"] }
    end

    private

    def build_candidate(business:, attributes: {})
      ActionCandidate.new(
        {
          business:,
          title: "Meta evaluator candidate",
          action_type: "seo_improvement",
          status: "idea",
          immediate_value_yen: 10_000,
          success_probability: 0.5,
          expected_hours: 1,
          generation_source: "ai_business"
        }.merge(attributes)
      )
    end

    def create_candidate(business:, action_type: "seo_improvement")
      build_candidate(business:, attributes: { action_type: }).tap(&:save!)
    end

    def create_action_result(business:, action_type:, actual_profit_yen:)
      action_candidate = ActionCandidate.create!(
        business:,
        title: "Evaluated #{SecureRandom.hex(4)}",
        action_type:,
        status: "done",
        immediate_value_yen: 1_000,
        success_probability: 1,
        expected_hours: 1,
        generation_source: "ai_business"
      )
      ActionResult.create!(
        action_candidate:,
        business:,
        executed_on: Date.current - 10,
        evaluated_on: Date.current,
        actual_profit_yen:,
        evaluation_status: "evaluated"
      )
    end

    def with_evaluators(results)
      evaluator_classes = results.map { |result| fake_evaluator(result) }
      original = MetaEvaluator::EVALUATORS
      MetaEvaluator.send(:remove_const, :EVALUATORS)
      MetaEvaluator.const_set(:EVALUATORS, evaluator_classes)
      yield
    ensure
      MetaEvaluator.send(:remove_const, :EVALUATORS)
      MetaEvaluator.const_set(:EVALUATORS, original)
    end

    def fake_evaluator(result)
      Class.new do
        define_method(:initialize) { |_action_candidate| }
        define_method(:call) { result }
      end
    end
  end
end
