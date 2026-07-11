require "test_helper"

module Aicoo
  class ActionExpectedValueRankingTest < ActiveSupport::TestCase
    Item = Data.define(
      :stable_id,
      :rank,
      :priority,
      :business_name,
      :expected_value_yen,
      :score
    )

    test "paginates twenty items and keeps global rank" do
      items = 25.times.map do |index|
        Item.new(
          stable_id: "action_candidate:#{index + 1}",
          rank: nil,
          priority: "improvement",
          business_name: "Business",
          expected_value_yen: 100_000 - index,
          score: 100_000 - index
        )
      end

      first_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 1).call
      second_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 2).call

      assert_equal 25, first_page.total_count
      assert_equal 20, first_page.items.size
      assert_equal 2, first_page.total_pages
      assert_equal 1, first_page.items.first.rank
      assert_equal "action_candidate:1", first_page.items.first.stable_id
      assert_equal 5, second_page.items.size
      assert_equal 21, second_page.items.first.rank
      assert_equal "action_candidate:21", second_page.items.first.stable_id
    end
  end
end
