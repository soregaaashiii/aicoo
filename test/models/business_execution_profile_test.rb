require "test_helper"

class BusinessExecutionProfileTest < ActiveSupport::TestCase
  test "sets safe defaults" do
    profile = BusinessExecutionProfile.create!(business: businesses(:suelog))

    assert_equal "aicoo_internal", profile.execution_type
    assert_equal "other", profile.repository_type
    assert_equal "main", profile.default_branch
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
      auto_deploy_enabled: true
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
        auto_deploy_enabled: true
      },
      profile.execution_target_config
    )
  end
end
