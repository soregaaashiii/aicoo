require "test_helper"

class BusinessExecutionProfileTest < ActiveSupport::TestCase
  test "sets safe defaults" do
    profile = BusinessExecutionProfile.create!(business: businesses(:suelog))

    assert_equal "aicoo_internal", profile.execution_type
    assert_equal "other", profile.repository_type
    assert_equal "main", profile.default_branch
    assert_equal "codex/auto-revision", profile.working_branch_prefix
    assert_equal "render", profile.deploy_target
    assert_equal "low", profile.auto_deploy_risk_limit
    assert_not profile.auto_merge_enabled?
    assert profile.require_manual_approval?
    assert_equal [], profile.target_paths
    assert_not profile.auto_deploy_enabled?
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

  test "stores codex execution target settings" do
    profile = BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      execution_type: "external_repo",
      github_repository: "owner/service",
      repository_path: "/apps/service",
      target_slug: "service-lp",
      target_paths_text: "app/views\napp/services",
      test_command: "bin/test",
      deploy_command: "bin/deploy",
      default_branch: "develop",
      working_branch_prefix: "codex/suelog",
      deploy_target: "render",
      render_service_name: "suelog-web",
      production_url: "https://suelog.example.com",
      health_check_url: "https://suelog.example.com/health",
      auto_deploy_enabled: true,
      auto_merge_enabled: true,
      auto_deploy_risk_limit: "medium",
      require_manual_approval: false
    )

    assert_equal [ "app/views", "app/services" ], profile.target_paths
    assert_equal "owner/service", profile.github_repo
    assert_equal "/apps/service", profile.local_project_path
    assert_equal(
      {
        execution_type: "external_repo",
        github_repo: "owner/service",
        local_project_path: "/apps/service",
        target_slug: "service-lp",
        target_paths: [ "app/views", "app/services" ],
        test_command: "bin/test",
        deploy_command: "bin/deploy",
        default_branch: "develop",
        working_branch_prefix: "codex/suelog",
        deploy_target: "render",
        render_service_name: "suelog-web",
        auto_deploy_enabled: true,
        auto_merge_enabled: true,
        auto_deploy_risk_limit: "medium",
        require_manual_approval: false,
        production_url: "https://suelog.example.com",
        health_check_url: "https://suelog.example.com/health"
      },
      profile.execution_target_config
    )
  end

  test "controls auto deploy by risk and approval settings" do
    profile = BusinessExecutionProfile.create!(
      business: businesses(:suelog),
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "owner/suelog",
      test_command: "bin/rails test",
      deploy_command: "bin/deploy",
      auto_deploy_enabled: true,
      auto_merge_enabled: true,
      auto_deploy_risk_limit: "medium",
      require_manual_approval: false
    )
    low_task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
    medium_task = AutoRevisionTask.from_action_candidate(create_candidate!("medium deploy task"))
    medium_task.update!(risk_level: "medium")
    high_task = AutoRevisionTask.from_action_candidate(create_candidate!("high deploy task"))
    high_task.update!(risk_level: "high")

    assert profile.auto_deploy_allowed_for?(low_task)
    assert profile.auto_deploy_allowed_for?(medium_task)
    assert_not profile.auto_deploy_allowed_for?(high_task)
    assert_equal "prompt_only_high_risk", profile.deploy_flow_for(high_task)
  end

  private

  def create_candidate!(title)
    ActionCandidate.create!(
      business: businesses(:suelog),
      title:,
      status: "approved",
      action_type: "seo_improvement",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1,
      execution_prompt: "SEOタイトルを改善してください。"
    )
  end
end
