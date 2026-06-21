require "test_helper"

module AicooJudge
  class ActionResultJudgeTest < ActiveSupport::TestCase
    test "aggregates action results by generation source business and action type" do
      suelog = businesses(:suelog)
      cards = businesses(:cards)
      create_result(business: suelog, generation_source: "ai_business", action_type: "seo_improvement", predicted: 10_000, actual: 8_000)
      create_result(business: cards, generation_source: "manual", action_type: "ui_improvement", predicted: 10_000, actual: 2_000)

      result = ActionResultJudge.new.call

      sources = result.generation_source_summaries.index_by(&:label)
      businesses = result.business_summaries.index_by(&:label)
      action_types = result.action_type_summaries.index_by(&:label)
      assert_equal 1, sources.fetch("ai_business").evaluated_count
      assert_equal 1, sources.fetch("manual").evaluated_count
      assert_equal 1, businesses.fetch(suelog.name).evaluated_count
      assert_equal 1, action_types.fetch("seo_improvement").evaluated_count
    end

    test "aggregates action results by metric rule" do
      create_result(metric_rule: "ctr_improvement", predicted: 10_000, actual: 9_000)

      result = ActionResultJudge.new.call
      metric_rules = result.metric_rule_summaries.index_by(&:label)

      assert_equal 1, metric_rules.fetch("ctr_improvement").evaluated_count
    end

    test "aggregates action results by metadata metric rule first" do
      create_result(metric_rule: "fallback_rule", metadata_metric_rule: "metadata_rule", predicted: 10_000, actual: 9_000)

      result = ActionResultJudge.new.call
      metric_rules = result.metric_rule_summaries.index_by(&:label)

      assert_equal 1, metric_rules.fetch("metadata_rule").evaluated_count
      assert_not metric_rules.key?("fallback_rule")
    end

    test "detects hits and big misses from prediction error rate" do
      hit = create_result(predicted: 10_000, actual: 8_000)
      big_miss = create_result(predicted: 10_000, actual: -15_000)

      result = ActionResultJudge.new.call

      assert_includes result.recent_hits, hit
      assert_includes result.recent_big_misses, big_miss
      assert_equal 1, result.overall_summary.big_miss_count
    end

    test "treats skipped records as count only and not accuracy data" do
      create_result(predicted: 10_000, actual: 8_000, status: "skipped")

      result = ActionResultJudge.new.call

      assert_equal 0, result.overall_summary.evaluated_count
      assert_equal 1, result.overall_summary.skipped_count
      assert_nil result.overall_summary.hit_rate
    end

    test "precision_for returns data shortage when matching data is missing" do
      action_candidate = action_candidates(:nagazakicho_article)

      precision = ActionResultJudge.new.precision_for(action_candidate)

      assert_equal 0, precision.fetch(:generation_source).evaluated_count
      assert_nil precision.fetch(:generation_source).hit_rate
    end

    private

    def create_result(business: businesses(:suelog), generation_source: "ai_business", action_type: "seo_improvement",
                      metric_rule: nil, metadata_metric_rule: nil, predicted:, actual:, status: "evaluated")
      action_candidate = ActionCandidate.create!(
        business:,
        title: "Judge action #{SecureRandom.hex(4)}",
        action_type:,
        generation_source:,
        immediate_value_yen: predicted,
        success_probability: 1,
        metadata: metadata_metric_rule ? { "metric_rule" => metadata_metric_rule } : {},
        evaluation_reason: metric_rule ? "metric_rule:#{metric_rule}" : "manual judge test"
      )
      ActionResult.create!(
        action_candidate:,
        business:,
        executed_on: Date.current - 10,
        evaluated_on: Date.current,
        actual_profit_yen: actual,
        evaluation_status: status
      )
    end
  end
end
