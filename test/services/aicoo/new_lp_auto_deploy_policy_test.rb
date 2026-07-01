require "test_helper"

module Aicoo
  class NewLpAutoDeployPolicyTest < ActiveSupport::TestCase
    setup do
      @business = Business.create!(
        name: "New LP Auto Deploy Test",
        description: "新規LP検証用",
        lifecycle_stage: "lp_validation",
        status: "idea",
        created_by_aicoo: true,
        new_lp_auto_deploy_enabled: true
      )
      @candidate = ActionCandidate.create!(
        business: @business,
        title: "LPを改善する",
        action_type: "build_mvp",
        status: "approved",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1,
        execution_prompt: "LPのMVPを小さく作る"
      )
      @task = AutoRevisionTask.from_action_candidate(@candidate, generated_by: "test")
      @task.update!(risk_level: "low")
    end

    test "allows only low risk new lp businesses" do
      result = NewLpAutoDeployPolicy.new(@task).call

      assert result.allowed?
      assert_equal [], result.reasons
    end

    test "excludes suelog and revenue businesses" do
      @business.update!(name: "吸えログ")

      result = NewLpAutoDeployPolicy.new(@task).call

      assert_not result.allowed?
      assert_includes result.reasons, "excluded_business"
    end

    test "rejects revenue businesses" do
      @business.revenue_events.create!(event_type: "revenue", amount: 1000, occurred_on: Date.current)

      result = NewLpAutoDeployPolicy.new(@task).call

      assert_not result.allowed?
      assert_includes result.reasons, "revenue_business"
    end

    test "rejects medium risk" do
      @task.update!(risk_level: "medium")

      result = NewLpAutoDeployPolicy.new(@task).call

      assert_not result.allowed?
      assert_includes result.reasons, "risk_not_low"
    end

    test "suspends business and records histories on failure" do
      auto_build_task = AutoBuildTask.create!(
        business: @business,
        auto_revision_task: @task,
        status: "pending",
        build_strategy: "priority_b",
        risk_level: "low"
      )

      assert_difference -> { BusinessActivityLog.where(activity_type: "new_lp_auto_deploy_auto_deploy_suspended").count }, 1 do
        NewLpAutoDeployPolicy.new(@task).suspend!(reason: "deploy failed", auto_build_task:)
      end

      assert @business.reload.auto_deploy_suspended?
      assert_equal "deploy failed", @business.auto_deploy_suspended_reason
      assert_equal "auto_deploy_suspended", auto_build_task.reload.metadata.fetch("auto_deploy_history").last.fetch("event")
      assert_equal "auto_deploy_suspended", @task.reload.metadata.fetch("auto_deploy_history").last.fetch("event")
    end
  end
end
