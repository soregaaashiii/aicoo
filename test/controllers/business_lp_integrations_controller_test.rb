require "test_helper"

class BusinessLpIntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = Business.create!(
      name: "外部AI受付テスト",
      description: "独立リポジトリで運用するAI受付",
      status: "building",
      business_type: "saas"
    )
  end

  test "redirects the retired LP integration page to the canonical business detail" do
    get business_lp_integration_url(@business)

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    follow_redirect!
    assert_response :success
    assert_select "#business-service-access-card"
    assert_select "#business-lp-access-card"
    assert_select "#business-measurement-access-card"
    assert_not_includes response.body, "LP・公開・計測セットアップ"
  end

  test "saves external repository source analytics and activity settings per business" do
    other_business = Business.create!(name: "別事業", status: "building", business_type: "saas")

    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    profile = @business.reload.business_execution_profile
    assert_equal "external_repo", profile.execution_type
    assert_equal "https://github.com/soregaaashiii/ai-reception", profile.codex_repository_url
    assert_equal "main", profile.codex_base_branch
    assert_equal "https://ai-reception.example.com", profile.production_url
    assert_equal "https://ai-reception.example.com/up", profile.health_check_url
    assert profile.require_manual_approval?

    prototype = @business.business_prototypes.find { |row| row.metadata["role"] == Aicoo::LpIntegration::Overview::ROLE }
    assert_equal "lovable_github", prototype.metadata["lp_source_type"]
    assert_equal "G-AIRECEPTION", prototype.metadata["ga4_measurement_id"]
    assert_not prototype.metadata.key?("source_code")

    site = AicooAnalyticsSite.find_by!(business: @business)
    assert_equal "123456789", site.ga4_property_id
    assert_equal "sc-domain:ai-reception.example.com", site.gsc_site_url

    connection = @business.source_app_connections.find { |row| row.metadata["role"] == Aicoo::LpIntegration::Overview::ROLE }
    assert connection.enabled?
    assert_equal "anonymous_aggregate_only", connection.settings["personal_data_policy"]
    assert_nil other_business.business_execution_profile
    assert_empty other_business.business_prototypes
  end

  test "creates a waiting approval task using the existing auto revision path" do
    @business.update!(auto_revision_mode: "automatic")
    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }

    assert_no_difference("Business.count") do
      assert_difference([ "ActionCandidate.count", "AutoRevisionTask.count", "CodexSubmission.count" ], 1) do
        post create_task_business_lp_integration_url(@business)
      end
    end

    task = @business.auto_revision_tasks.order(:created_at).last
    assert_redirected_to auto_revision_task_url(task)
    assert_equal "revenue", task.action_candidate.department
    assert_equal true, task.action_candidate.metadata["manual_task_creation_only"]
    assert_equal "waiting_approval", task.status
    assert_equal "external_lp_import", task.metadata["workflow_type"]
    assert_equal false, task.metadata["auto_deploy_enabled"]
    assert_equal "draft", task.codex_submission.status
    assert_includes task.codex_submission.prompt, "https://github.com/soregaaashiii/ai-reception"
    assert_includes task.codex_submission.prompt, "AICOOのリポジトリを変更しない"
    assert_includes task.codex_submission.prompt, "AICOO_INTEGRATION_ENABLED=false"
    assert_includes task.codex_submission.prompt, "contact_submit"
    assert_equal 1, task.action_candidate.auto_revision_tasks.count
  end

  test "does not duplicate an active task for the same settings" do
    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }
    post create_task_business_lp_integration_url(@business)
    task = @business.auto_revision_tasks.last

    assert_no_difference([ "ActionCandidate.count", "AutoRevisionTask.count" ]) do
      post create_task_business_lp_integration_url(@business)
    end

    assert_redirected_to auto_revision_task_url(task)
  end

  test "keeps legacy task actions available without restoring the retired screen" do
    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }
    post create_task_business_lp_integration_url(@business)

    get business_lp_integration_url(@business)

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    assert_equal "waiting_approval", @business.auto_revision_tasks.order(:created_at).last.status
  end

  test "completed legacy settings remain visible from the business detail" do
    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }

    get business_lp_integration_url(@business)

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    follow_redirect!
    assert_response :success
    assert_includes response.body, "https://github.com/soregaaashiii/ai-reception"
    assert_includes response.body, "123456789"
    assert_not_includes response.body, "LP・公開・計測セットアップ"
  end

  private

  def valid_settings
    {
      lp_source_type: "lovable_github",
      lp_source_repository_url: "https://github.com/example/ai-reception-lp",
      lp_source_branch: "main",
      lp_source_url: "https://ai-reception.lovable.app",
      app_repository_url: "https://github.com/soregaaashiii/ai-reception",
      app_branch: "main",
      app_framework: "rails",
      marketing_root_path: "app/views/marketing",
      production_url: "https://ai-reception.example.com",
      render_service_name: "ai-reception-web",
      health_check_url: "https://ai-reception.example.com/up",
      ga4_property_id: "123456789",
      ga4_measurement_id: "G-AIRECEPTION",
      gsc_site_url: "sc-domain:ai-reception.example.com",
      integration_enabled: "1",
      activity_api_enabled: "1",
      auto_deploy_enabled: "0",
      manual_approval_required: "1"
    }
  end
end
