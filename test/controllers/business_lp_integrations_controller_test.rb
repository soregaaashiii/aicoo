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

  test "opens the LP integration page for a registered business" do
    get business_lp_integration_url(@business)

    assert_response :success
    assert_includes response.body, "LP・公開・計測セットアップ"
    assert_includes response.body, "aria-valuenow=\"0\""
    assert_includes response.body, "GitHubを登録"
    assert_includes response.body, "Lovableを接続"
    assert_includes response.body, "Renderを登録"
    assert_includes response.body, "GA4を接続"
    assert_includes response.body, "GSCを接続"
    assert_includes response.body, "Activity APIを接続"
    assert_includes response.body, new_admin_business_execution_profile_path(business_id: @business.id).gsub("&", "&amp;")
    assert_includes response.body, google_settings_business_path(@business, anchor: "business-google-settings")
    assert_includes response.body, "次にやること"
    assert_includes response.body, "AICOOは設定・タスク・匿名化した成果だけを保持します"
  end

  test "saves external repository source analytics and activity settings per business" do
    other_business = Business.create!(name: "別事業", status: "building", business_type: "saas")

    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }

    assert_redirected_to business_lp_integration_url(@business)
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

  test "shows analytics states and sync history" do
    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }
    post create_task_business_lp_integration_url(@business)

    get business_lp_integration_url(@business)

    assert_response :success
    assert_includes response.body, "GA4"
    assert_includes response.body, "GSC"
    assert_includes response.body, "Activity API"
    assert_includes response.body, "同期履歴"
    assert_includes response.body, "https://github.com/soregaaashiii/ai-reception"
    assert_includes response.body, "承認待ち"
  end

  test "shows only the operational actions when setup is complete" do
    patch business_lp_integration_url(@business), params: { lp_integration: valid_settings }

    get business_lp_integration_url(@business)

    assert_response :success
    assert_includes response.body, "セットアップ完了"
    assert_includes response.body, "aria-valuenow=\"100\""
    assert_includes response.body, "LP同期"
    assert_includes response.body, "本番確認"
    assert_includes response.body, "分析開始"
    assert_not_includes response.body, "GitHubを登録"
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
