require "test_helper"

module Aicoo
  class OpportunityDiscoverySummaryTest < ActiveSupport::TestCase
    test "owner home result matches the displayed fields" do
      full = OpportunityDiscoverySummary.new.call
      owner_home = OpportunityDiscoverySummary.new.call_for_owner_home

      OpportunityDiscoverySummary::OwnerHomeResult.members.each do |field|
        expected = full.public_send(field)
        expected = expected.to_a if expected.respond_to?(:to_sql)
        assert_equal expected, owner_home.public_send(field), field
      end
    end
  end
end
