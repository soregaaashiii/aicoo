require "test_helper"

module Aicoo
  class ActionExpectedValueRankingTest < ActiveSupport::TestCase
    Item = Data.define(
      :stable_id,
      :rank,
      :priority,
      :business_name,
      :expected_value_yen,
      :score,
      :record,
      :action_expected_value_delta_yen,
      :confidence,
      :valuation_status
    )

    test "paginates twenty items and keeps global rank" do
      items = 45.times.map do |index|
        Item.new(
          stable_id: "action_candidate:#{index + 1}",
          rank: nil,
          priority: "improvement",
          business_name: "Business",
          expected_value_yen: 100_000 - index,
          score: 100_000 - index,
          record: nil,
          action_expected_value_delta_yen: 100_000 - index,
          confidence: 0.8,
          valuation_status: "positive"
        )
      end

      first_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 1).call
      second_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 2).call
      third_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 3).call

      assert_equal 45, first_page.total_count
      assert_equal 20, first_page.items.size
      assert_equal 3, first_page.total_pages
      assert_equal 1, first_page.items.first.rank
      assert_equal "action_candidate:1", first_page.items.first.stable_id
      assert_equal 20, second_page.items.size
      assert_equal 21, second_page.items.first.rank
      assert_equal "action_candidate:21", second_page.items.first.stable_id
      assert_equal 5, third_page.items.size
      assert_equal 41, third_page.items.first.rank
      assert_equal "action_candidate:41", third_page.items.first.stable_id
    end

    test "ranks avoided loss by positive action delta instead of raw negative loss" do
      recovery = item(
        stable_id: "daily_run_issue:stuck",
        delta: 700_000,
        no_action: -1_000_000,
        action: -200_000,
        cost: 100_000,
        confidence: 0.8
      )
      neutral = item(stable_id: "action_candidate:neutral", delta: 0, confidence: 1)
      negative = item(stable_id: "new_business:negative", delta: -500, confidence: 0.9)

      result = ActionExpectedValueRanking.new(items: [ negative, neutral, recovery ], mode: "revenue").call

      assert_equal [ "daily_run_issue:stuck", "action_candidate:neutral", "new_business:negative" ], result.items.map(&:stable_id)
      assert_equal 700_000, result.items.first.action_expected_value_delta_yen
    end

    test "excludes unvalued items from ranking instead of treating them as zero" do
      unvalued = item(stable_id: "action_candidate:unvalued", delta: 0, confidence: 1, valuation_status: "unvalued")
      valued = item(stable_id: "action_candidate:valued", delta: 1, confidence: 0.5)

      result = ActionExpectedValueRanking.new(items: [ unvalued, valued ], mode: "revenue").call

      assert_equal [ "action_candidate:valued" ], result.items.map(&:stable_id)
    end

    test "excludes action candidate records with external or invalid target urls" do
      external = action_candidate(
        title: "外部URL改善",
        metadata: { "target_url_type" => "external_reference", "target_url" => nil }
      )
      invalid = action_candidate(
        title: "不正URL改善",
        metadata: { "target_url_type" => "invalid", "target_url" => nil }
      )
      valid = action_candidate(
        title: "自社URL改善",
        metadata: { "target_url_type" => "own_existing", "target_url" => "/" }
      )

      result = ActionExpectedValueRanking.new(
        items: [
          item(stable_id: "action_candidate:external", delta: 10_000, confidence: 1, record: external),
          item(stable_id: "action_candidate:invalid", delta: 9_000, confidence: 1, record: invalid),
          item(stable_id: "action_candidate:valid", delta: 1_000, confidence: 1, record: valid)
        ],
        mode: "revenue"
      ).call

      assert_equal [ "action_candidate:valid" ], result.items.map(&:stable_id)
    end

    private

    def item(stable_id:, delta:, confidence:, valuation_status: nil, no_action: 0, action: nil, cost: 0, record: nil)
      Item.new(
        stable_id:,
        rank: nil,
        priority: "improvement",
        business_name: "Business",
        expected_value_yen: delta,
        score: delta,
        record:,
        action_expected_value_delta_yen: delta,
        confidence:,
        valuation_status: valuation_status || (delta.positive? ? "positive" : (delta.negative? ? "negative" : "neutral"))
      )
    end

    def action_candidate(title:, metadata:)
      ActionCandidate.create!(
        business: businesses(:suelog),
        title:,
        action_type: "seo_improvement",
        generation_source: "business_analyzer",
        immediate_value_yen: 1_000,
        success_probability: 0.5,
        expected_hours: 1,
        metadata:
      )
    end
  end
end
