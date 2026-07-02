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

  test "validates business type" do
    business = Business.new(name: "Test", status: "idea", business_type: "unknown")

    assert_not business.valid?
    assert_includes business.errors[:business_type], "is not included in the list"
  end

  test "fixtures classify known businesses" do
    assert_equal "seo_media", businesses(:suelog).business_type
    assert_equal "saas", businesses(:cards).business_type
  end
end
