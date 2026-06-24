require "test_helper"

class OpportunityDiscoveryItemTest < ActiveSupport::TestCase
  test "sets defaults" do
    item = OpportunityDiscoveryItem.create!(title: "Owner insight")

    assert_equal "owner_discovery", item.source_type
    assert_equal "new", item.status
    assert_equal 50, item.opportunity_score
    assert item.discovered_at.present?
  end

  test "converts to action candidate" do
    item = OpportunityDiscoveryItem.create!(
      business: businesses(:suelog),
      title: "表示回数が多い記事を伸ばす",
      description: "CTR改善より儲かるかもしれない",
      opportunity_score: 80
    )

    assert_difference("ActionCandidate.count", 1) do
      candidate = item.convert_to_action_candidate!
      assert_equal "opportunity_validation", candidate.action_type
      assert_equal "opportunity_discovery", candidate.generation_source
      assert_equal "converted", item.reload.status
      assert_equal item.id, candidate.metadata["opportunity_id"]
    end
  end
end
