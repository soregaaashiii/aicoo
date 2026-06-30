require "test_helper"

module Admin
  class SourceAppDiffRulesControllerTest < ActionDispatch::IntegrationTest
    test "shows and updates diff rules" do
      connection = SourceAppConnection.ensure_suelog_defaults!
      rule = connection.source_app_diff_rules.first

      get admin_source_app_diff_rules_url
      assert_response :success
      assert_includes response.body, "Source App Diff Rules"

      patch admin_source_app_diff_rule_url(rule), params: {
        source_app_diff_rule: {
          name: rule.name,
          watched_table: rule.watched_table,
          resource_type: rule.resource_type,
          activity_type: rule.activity_type,
          title_template: rule.title_template,
          estimated_work_seconds: 45,
          enabled: "1",
          priority: 5,
          watched_fields: "name,area",
          metadata_fields: "area"
        }
      }

      assert_redirected_to admin_source_app_diff_rules_url
      assert_equal 45, rule.reload.estimated_work_seconds
      assert_equal %w[name area], rule.watched_fields
    end
  end
end
