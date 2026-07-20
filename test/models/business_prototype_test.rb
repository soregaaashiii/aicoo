require "test_helper"

class BusinessPrototypeTest < ActiveSupport::TestCase
  test "accepts supported prototype types" do
    prototype = BusinessPrototype.new(
      business: businesses(:suelog),
      prototype_type: "github",
      location: "https://github.com/example/service"
    )

    assert prototype.valid?
  end

  test "requires an http url for url based prototype types" do
    prototype = BusinessPrototype.new(
      business: businesses(:suelog),
      prototype_type: "url",
      location: "not-a-url"
    )

    assert_not prototype.valid?
    assert_includes prototype.errors[:location], "はhttp(s) URLを入力してください"
  end

  test "allows a local path for local prototypes" do
    prototype = BusinessPrototype.new(
      business: businesses(:suelog),
      prototype_type: "local",
      location: "/projects/service"
    )

    assert prototype.valid?
  end
end
