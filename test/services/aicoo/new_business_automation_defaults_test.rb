require "test_helper"

module Aicoo
  class NewBusinessAutomationDefaultsTest < ActiveSupport::TestCase
    test "enables automation and codex auto submit for aicoo-created new business" do
      business = Business.create!(
        name: "新規事業デフォルトON",
        description: "SERPから見つかった新規事業",
        status: "idea",
        source: "serp",
        created_by_aicoo: true,
        launched: false,
        lifecycle_stage: "lp_validation",
        business_type: "landing_page"
      )

      Aicoo::NewBusinessAutomationDefaults.apply!(business)

      business.reload
      assert business.daily_run_enabled?
      assert business.serp_enabled?
      assert_equal "automatic", business.auto_revision_mode
      assert_equal "approval", business.auto_deploy_mode
      assert business.auto_build_enabled?
      assert_not business.auto_build_requires_approval?
      assert business.new_lp_auto_deploy_enabled?

      profile = business.business_execution_profile
      assert profile
      assert_equal "aicoo_internal", profile.execution_type
      assert profile.codex_enabled?
      assert profile.codex_auto_submit_enabled?
      assert profile.codex_auto_pr_enabled?
      assert_not profile.codex_auto_merge_enabled?
      assert_not profile.codex_auto_deploy_enabled?
      assert_equal "medium", profile.codex_risk_limit
      assert_equal "https://github.com/soregaaashiii/aicoo", profile.codex_repository_url
      assert_equal "bin/rails test", profile.test_command
      assert_equal "bin/rails zeitwerk:check", profile.lint_command
    end

    test "does not enable automation for normal existing business" do
      business = Business.create!(
        name: "通常既存事業",
        description: "Ownerが手動で管理する通常事業",
        status: "launched",
        created_by_aicoo: false,
        lifecycle_stage: "production",
        business_type: "saas",
        auto_revision_mode: "manual"
      )

      Aicoo::NewBusinessAutomationDefaults.apply!(business)

      business.reload
      assert_equal "manual", business.auto_revision_mode
      assert_nil business.business_execution_profile
    end
  end
end
