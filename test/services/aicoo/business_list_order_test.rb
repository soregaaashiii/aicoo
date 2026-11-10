require "test_helper"

class Aicoo::BusinessListOrderTest < ActiveSupport::TestCase
  test "moves a business and stores a stable list order without changing timestamps" do
    businesses = Aicoo::BusinessListOrder.sort(Business.real_businesses.to_a)
    moving_business = businesses.first
    next_business = businesses.second
    moving_updated_at = moving_business.updated_at

    assert Aicoo::BusinessListOrder.move(moving_business, direction: "down")

    reordered = Aicoo::BusinessListOrder.sort(Business.real_businesses.reload.to_a)
    assert_equal next_business.id, reordered.first.id
    assert_equal moving_business.id, reordered.second.id
    assert_equal moving_updated_at, moving_business.reload.updated_at
  end

  test "moves a business directly to any requested position" do
    businesses = Aicoo::BusinessListOrder.sort(Business.real_businesses.to_a)
    moving_business = businesses.last

    assert Aicoo::BusinessListOrder.move(moving_business, target_position: 1)

    reordered = Aicoo::BusinessListOrder.sort(Business.real_businesses.reload.to_a)
    assert_equal moving_business.id, reordered.first.id
  end

  test "rejects an out of range requested position" do
    business = Aicoo::BusinessListOrder.sort(Business.real_businesses.to_a).first

    assert_not Aicoo::BusinessListOrder.move(business, target_position: 0)
    assert_not Aicoo::BusinessListOrder.move(business, target_position: Business.real_businesses.count + 1)
  end

  test "does not move past the list boundary or accept an unknown direction" do
    first_business = Aicoo::BusinessListOrder.sort(Business.real_businesses.to_a).first

    assert_not Aicoo::BusinessListOrder.move(first_business, direction: "up")
    assert_not Aicoo::BusinessListOrder.move(first_business, direction: "sideways")
  end

  test "places businesses without a saved position after explicitly ordered businesses" do
    ordered_business, unordered_business = Business.real_businesses.order(:name).first(2)
    ordered_business.update_columns(
      metadata: ordered_business.metadata.to_h.merge(Aicoo::BusinessListOrder::POSITION_KEY => 0)
    )

    sorted = Aicoo::BusinessListOrder.sort([ unordered_business.reload, ordered_business.reload ])

    assert_equal [ ordered_business.id, unordered_business.id ], sorted.map(&:id)
  end
end
