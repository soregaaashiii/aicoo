require "test_helper"

module Aicoo
  class NewBusinessCandidateBoardTest < ActiveSupport::TestCase
    test "lists active new business action candidates" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "新規事業候補: 警備AI",
        description: "警備AIのLP検証",
        action_type: "build_lp",
        department: "new_business",
        generation_source: "integrated_decision",
        status: "idea",
        immediate_value_yen: 80_000,
        success_probability: 0.25,
        expected_hours: 2,
        metadata: {
          "candidate_kind" => "new_business",
          "source_query" => "警備 AI",
          "market_memo" => "上位にSaaS競合あり"
        }
      )

      result = Aicoo::NewBusinessCandidateBoard.call(limit: 5)

      assert_includes result.candidates.map(&:action_candidate), candidate
      row = result.candidates.find { |entry| entry.action_candidate == candidate }
      assert_equal "警備 AI", row.source_query
      assert_equal "上位にSaaS競合あり", row.market_memo
      assert_operator result.pending_count, :>=, 1
    end

    test "returns zero reasons when no candidates exist" do
      ActionCandidate.where(generation_source: "integrated_decision").delete_all

      result = Aicoo::NewBusinessCandidateBoard.call(limit: 5)

      assert_empty result.candidates
      assert_not_empty result.zero_reasons
    end
  end
end
