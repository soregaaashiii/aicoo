require "test_helper"

class BusinessTest < ActiveSupport::TestCase
  test "requires name" do
    business = Business.new(status: "idea")

    assert_not business.valid?
  end

  test "separates system businesses from real businesses" do
    real = Business.create!(name: "吸えログ", status: "launched")
    system = Business.create!(name: "AICOO Analytics Import", status: "launched")

    assert_includes Business.real_businesses, real
    assert_not_includes Business.real_businesses, system
    assert_predicate system, :system_business?
    assert_not real.system_business?
  end
end
