require "test_helper"

class BusinessAccessSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = Business.create!(
      name: "公開設定テスト事業",
      description: "公開確認URLの直接編集テスト",
      status: "launched",
      business_type: "landing_page"
    )
    @other_business = Business.create!(
      name: "別事業",
      description: "設定分離テスト",
      status: "launched",
      business_type: "saas"
    )
  end

  test "business detail shows direct registration buttons when access settings are missing" do
    get business_url(@business)

    assert_response :success
    assert_includes response.body, "公開確認URL"
    assert_includes response.body, "Service URLを登録"
    assert_includes response.body, "LPを登録"
    assert_includes response.body, "本番URLを登録"
    assert_includes response.body, "business-access-grid"
  end

  test "service settings save to the scoped service and execution profile" do
    unrelated_service = @other_business.business_services.create!(
      name: "別事業Service",
      url: "https://other.example.com",
      status: "live"
    )
    patch service_business_access_settings_url(@business), params: {
      service_access: {
        business_service_id: unrelated_service.id,
        service_url: "https://service.example.com",
        domain: "service.example.com",
        github_repository: "https://github.com/example/service",
        branch: "main"
      }
    }

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    service = @business.business_services.reload.sole
    profile = @business.reload.business_execution_profile
    assert_equal "https://service.example.com", service.url
    assert_equal "service.example.com", service.domain
    assert_equal "https://github.com/example/service", profile.github_repository
    assert_equal "main", profile.default_branch
    assert_equal "https://other.example.com", unrelated_service.reload.url
    assert_nil @other_business.reload.business_execution_profile

    get business_url(@business)
    assert_includes response.body, "接続済み"
    assert_includes response.body, "https://service.example.com"
    assert_includes response.body, "https://github.com/example/service"
  end

  test "landing page settings save to the scoped prototype and create an import task" do
    patch landing_page_business_access_settings_url(@business), params: {
      lp_access: {
        source_type: "lovable_github",
        source_repository_url: "https://github.com/example/lp-source",
        source_branch: "main",
        lovable_project_url: "https://lovable.dev/projects/example",
        public_url: "https://lp.example.com",
        public_status: "published",
        app_repository_url: "https://github.com/example/service",
        app_branch: "main"
      }
    }

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    prototype = @business.business_prototypes.reload.sole
    metadata = prototype.metadata.to_h
    assert_equal Aicoo::LpIntegration::Overview::ROLE, metadata["role"]
    assert_equal "lovable_github", metadata["lp_source_type"]
    assert_equal "https://github.com/example/lp-source", metadata["lp_source_repository_url"]
    assert_equal "https://lovable.dev/projects/example", metadata["lovable_project_url"]
    assert_equal "https://lp.example.com", metadata["lp_public_url"]
    assert_equal "published", metadata["lp_public_status"]
    assert_empty @other_business.business_prototypes.reload

    get business_url(@business)
    assert_includes response.body, "登録済み"
    assert_includes response.body, "Lovable GitHub"
    assert_includes response.body, "https://github.com/example/lp-source"
    assert_includes response.body, "https://lp.example.com"

    assert_difference [ "ActionCandidate.count", "AutoRevisionTask.count" ], 1 do
      post landing_page_task_business_access_settings_url(@business)
    end
    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    assert_equal "external_lp_import", @business.auto_revision_tasks.order(:created_at).last.metadata.to_h["workflow_type"]
  end

  test "production settings save to the scoped execution profile" do
    patch production_business_access_settings_url(@business), params: {
      production_access: {
        production_url: "https://production.example.com",
        health_check_url: "https://production.example.com/up",
        render_service_name: "production-web",
        deploy_target: "render",
        auto_deploy_enabled: "1"
      }
    }

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    profile = @business.reload.business_execution_profile
    assert_equal "https://production.example.com", profile.production_url
    assert_equal "https://production.example.com/up", profile.health_check_url
    assert_equal "production-web", profile.render_service_name
    assert_equal "render", profile.deploy_target
    assert profile.auto_deploy_enabled?
    assert_nil @other_business.reload.business_execution_profile

    get business_url(@business)
    assert_includes response.body, "接続済み"
    assert_includes response.body, "https://production.example.com"
    assert_includes response.body, "production-web"
    assert_includes response.body, "接続確認"
  end
end
