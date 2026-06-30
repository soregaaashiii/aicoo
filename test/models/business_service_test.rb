require "test_helper"

class BusinessServiceTest < ActiveSupport::TestCase
  test "requires valid status" do
    service = BusinessService.new(business: businesses(:suelog), name: "Test", status: "unknown")

    assert_not service.valid?
  end
end
