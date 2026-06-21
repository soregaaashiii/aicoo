require "test_helper"

class DataSourceTest < ActiveSupport::TestCase
  test "requires supported source type" do
    data_source = DataSource.new(business: businesses(:suelog), name: "Bad source", source_type: "bad")

    assert_not data_source.valid?
  end
end
