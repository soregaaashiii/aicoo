require "test_helper"

class BusinessExecutionProfileTest < ActiveSupport::TestCase
  test "sets safe defaults" do
    profile = BusinessExecutionProfile.create!(business: businesses(:suelog))

    assert_equal "other", profile.repository_type
    assert_equal "main", profile.default_branch
    assert profile.active?
    assert_includes profile.forbidden_pattern_lines, "db:drop"
    assert_includes profile.forbidden_pattern_lines, "db:reset"
    assert_includes profile.forbidden_pattern_lines, "drop database"
  end

  test "business can have only one execution profile" do
    BusinessExecutionProfile.create!(business: businesses(:suelog), repository_name: "suelog")
    duplicate = BusinessExecutionProfile.new(business: businesses(:suelog), repository_name: "another")

    assert_not duplicate.valid?
  end
end
