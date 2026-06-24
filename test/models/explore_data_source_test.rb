require "test_helper"

class ExploreDataSourceTest < ActiveSupport::TestCase
  test "creates explore data source with defaults" do
    source = ExploreDataSource.create!(name: "Google Trends", source_type: "google_trends")

    assert source.enabled?
    assert_equal "inactive", source.status
  end
end
