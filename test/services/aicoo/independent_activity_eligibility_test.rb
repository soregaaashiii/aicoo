require "test_helper"

module Aicoo
  class IndependentActivityEligibilityTest < ActiveSupport::TestCase
    test "includes suelog shop and article user activities" do
      activities = [
        [ "shop_created", "Shop" ],
        [ "shop_profile_updated", "Shop" ],
        [ "shop_deleted", "Shop" ],
        [ "business_hours_updated", "Shop" ],
        [ "smoking_status_updated", "Shop" ],
        [ "article_created", "Article" ],
        [ "article_updated", "Article" ],
        [ "article_deleted", "Article" ],
        [ "title_changed", "Article" ],
        [ "content_updated", "Article" ],
        [ "internal_link_added", "Article" ],
        [ "seo_improvement", "Article" ]
      ]

      activities.each do |activity_type, resource_type|
        result = IndependentActivityEligibility.call(activity_log(source_app: "suelog", activity_type:, resource_type:))

        assert result.included?, "expected #{activity_type} to be included"
        assert_equal "suelog", result.source_app
        assert_equal resource_type, result.source_model
        assert_equal "suelog_user_activity", result.included_reason
        assert_equal true, result.is_suelog_activity
        assert_equal false, result.is_internal_event
      end
    end

    test "excludes aicoo internal events even if their source app says suelog" do
      activities = [
        [ "landing_page_create", "AicooLabLandingPage" ],
        [ "landing_page_update", "AicooLabLandingPage" ],
        [ "landing_page_published", "AicooLabLandingPage" ],
        [ "activity_api_diagnostic", "Article" ],
        [ "action_result_update", "ActionResult" ],
        [ "daily_run_started", "AicooDailyRun" ],
        [ "calibration_updated", "Calibration" ]
      ]

      activities.each do |activity_type, resource_type|
        result = IndependentActivityEligibility.call(activity_log(source_app: "suelog", activity_type:, resource_type:))

        assert_not result.included?, "expected #{activity_type} to be excluded"
        assert_equal "internal_event", result.excluded_reason
        assert_equal true, result.is_internal_event
        assert_equal false, result.is_suelog_activity
      end
    end

    test "excludes non suelog and unsupported model activities" do
      aicoo = IndependentActivityEligibility.call(
        activity_log(source_app: "aicoo", activity_type: "shop_created", resource_type: "Shop")
      )
      landing_page = IndependentActivityEligibility.call(
        activity_log(source_app: "suelog", activity_type: "custom_updated", resource_type: "LandingPage")
      )

      assert_equal "internal_event", aicoo.excluded_reason
      assert_equal "unsupported_source_model", landing_page.excluded_reason
    end

    private

    def activity_log(source_app:, activity_type:, resource_type:)
      BusinessActivityLog.new(
        source_app:,
        activity_type:,
        resource_type:,
        resource_id: "1"
      )
    end
  end
end
