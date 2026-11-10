require "test_helper"

class BusinessServiceTest < ActiveSupport::TestCase
  test "requires valid status" do
    service = BusinessService.new(business: businesses(:suelog), name: "Test", status: "unknown")

    assert_not service.valid?
  end

  test "reference pages do not replace the user page" do
    service = BusinessService.new(
      business: businesses(:suelog),
      name: "Reference pages",
      status: "live",
      url: "https://service.example.com",
      admin_url: "https://service.example.com/admin",
      other_url: "https://status.example.com"
    )

    assert_equal "https://service.example.com", service.display_url
    assert_equal "https://service.example.com/admin", service.metadata["admin_url"]
    assert_equal "https://status.example.com", service.metadata["other_url"]
  end
end
