require "test_helper"

class BusinessTest < ActiveSupport::TestCase
  test "requires name" do
    business = Business.new(status: "idea")

    assert_not business.valid?
  end

  test "separates system businesses from real businesses" do
    real = Business.create!(name: "吸えログ", status: "launched")
    system = Business.create!(name: "AICOO Analytics Import", status: "launched")

    assert_includes Business.real_businesses, real
    assert_not_includes Business.real_businesses, system
    assert_predicate system, :system_business?
    assert_not real.system_business?
  end

  test "soft deleted businesses are excluded from real businesses and automation is stopped" do
    business = Business.create!(
      name: "SERP誤生成Business",
      status: "exploring",
      daily_run_enabled: true,
      serp_enabled: true,
      auto_revision_mode: "automatic",
      auto_build_enabled: true,
      auto_deploy_mode: "automatic",
      new_lp_auto_deploy_enabled: true
    )

    business.soft_delete!(reason: "SERP誤生成", actor: "owner", source: "test")

    assert business.deleted?
    assert_not_includes Business.real_businesses, business
    assert_not business.daily_run_enabled?
    assert_not business.serp_enabled?
    assert_equal "manual", business.auto_revision_mode
    assert_not business.auto_build_enabled?
    assert_equal "manual", business.auto_deploy_mode
    assert_not business.new_lp_auto_deploy_enabled?
    assert_equal "archived", business.resource_status
    assert_equal "SERP誤生成", business.deletion_reason
    assert business.business_activity_logs.where(activity_type: "business_delete").exists?
  end

  test "soft delete supersedes unfinished ai business action candidates" do
    business = Business.create!(name: "削除予定のAI事業", status: "exploring")
    active_candidate = business.action_candidates.create!(
      title: "削除予定のAI事業を改善する",
      action_type: "build_mvp",
      generation_source: "ai_business",
      status: "idea",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1
    )
    completed_candidate = business.action_candidates.create!(
      title: "完了済み施策",
      action_type: "build_mvp",
      generation_source: "ai_business",
      status: "done",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1
    )

    business.soft_delete!(reason: "SERP誤生成", actor: "owner", source: "test")

    assert_equal "superseded", active_candidate.reload.status
    assert_equal "deleted_business_ai_business_candidate", active_candidate.metadata["ranking_cleanup_reason"]
    assert_equal business.id, active_candidate.metadata["deleted_business_id"]
    assert_equal "done", completed_candidate.reload.status
  end

  test "restores soft deleted business to previous status" do
    business = Business.create!(name: "復元対象Business", status: "exploring", serp_enabled: true)
    business.soft_delete!(reason: "既存事業との重複", actor: "owner", source: "test")

    business.restore_from_soft_delete!(actor: "owner")

    assert_not business.deleted?
    assert_includes Business.real_businesses, business
    assert_equal "exploring", business.status
    assert_equal "既存事業との重複", business.business_activity_logs.where(activity_type: "business_delete").last.metadata["reason"]
    assert business.business_activity_logs.where(activity_type: "business_restore").exists?
  end

  test "validates business type" do
    business = Business.new(name: "Test", status: "idea", business_type: "unknown")

    assert_not business.valid?
    assert_includes business.errors[:business_type], "is not included in the list"
  end

  test "fixtures classify known businesses" do
    assert_equal "seo_media", businesses(:suelog).business_type
    assert_equal "saas", businesses(:cards).business_type
  end
end
