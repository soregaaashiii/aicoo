require "test_helper"

class BusinessTest < ActiveSupport::TestCase
  test "requires name" do
    business = Business.new(status: "idea")

    assert_not business.valid?
  end
end
