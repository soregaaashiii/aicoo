require "test_helper"

module Aicoo
  class BusinessIndexCandidateOverviewTest < ActiveSupport::TestCase
    test "loads serp business ids and pending count in one query" do
      business = businesses(:suelog)
      ActionCandidate.create!(
        business:,
        title: "一覧SERP候補",
        action_type: "new_business",
        generation_source: "serp",
        department: "new_business",
        status: "idea"
      )
      expected_pending_count = Aicoo::NewBusinessCandidateBoard.pending_count
      query_names = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        query_names << payload[:name] unless payload[:name] == "SCHEMA"
      end

      result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        BusinessIndexCandidateOverview.call([ business ])
      end

      assert_includes result.serp_business_ids, business.id
      assert_equal expected_pending_count, result.new_business_pending_count
      assert_equal [ "Business index candidate overview" ], query_names
    end

    test "keeps the global pending count when the business collection is empty" do
      expected_pending_count = Aicoo::NewBusinessCandidateBoard.pending_count

      result = BusinessIndexCandidateOverview.call([])

      assert_empty result.serp_business_ids
      assert_equal expected_pending_count, result.new_business_pending_count
    end
  end
end
