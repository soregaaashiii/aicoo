require "test_helper"

class BusinessesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:suelog)
  end

  test "should get index" do
    get businesses_url
    assert_response :success
    assert_includes response.body, "Health"
    assert_includes response.body, "Last Sync"
    assert_includes response.body, "GSC 7日 / 30日"
    assert_includes response.body, "GA4 7日 / 30日"
    assert_includes response.body, "接続状態"
    assert_includes response.body, "Revenue 7日 / 30日"
    assert_includes response.body, "Data Source Cost"
    assert_includes response.body, "Pending Actions"
    assert_includes response.body, "Warning"
    assert_includes response.body, "Analytics"
    assert_includes response.body, "Execution Profile"
    assert_includes response.body, "missing"
    assert_includes response.body, "Profile作成"
    assert_includes response.body, "CODEX"
  end

  test "index shows execution profile coverage status" do
    BusinessExecutionProfile.create!(
      business: @business,
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      test_command: "bin/rails test",
      deploy_command: "bin/deploy"
    )

    get businesses_url

    assert_response :success
    assert_includes response.body, "configured"
    assert_includes response.body, "suelog"
    assert_includes response.body, "Profile編集"
  end

  test "should get new" do
    get new_business_url
    assert_response :success
  end

  test "should create business" do
    assert_difference("Business.count") do
      post businesses_url, params: { business: { description: @business.description, name: "新規事業探索", status: @business.status } }
    end

    assert_redirected_to business_url(Business.last)
  end

  test "should show business" do
    @business.revenue_events.create!(occurred_on: Date.current, event_type: "revenue", amount: 10_000)
    @business.revenue_events.create!(occurred_on: Date.current, event_type: "expense", amount: 3_000)
    @business.business_metric_dailies.create!(recorded_on: Date.current, impressions: 1_000, clicks: 10)
    @business.analysis_candidates.create!(
      analysis_source: "serp",
      expected_value_yen: 1_500,
      estimated_cost_yen: 20,
      estimated_minutes: 30,
      roi: 75,
      confidence: 60,
      priority: 90,
      execution_mode: "manual",
      reason: "順位急落を確認するためSERP分析を推奨",
      due_on: Date.current
    )

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "Business Analytics Dashboard"
    assert_includes response.body, "Connection Status"
    assert_includes response.body, "GSCグラフ"
    assert_includes response.body, "GA4グラフ"
    assert_includes response.body, "Revenueグラフ"
    assert_includes response.body, "Actionグラフ"
    assert_includes response.body, "Learningグラフ"
    assert_includes response.body, "clicks"
    assert_includes response.body, "sessions"
    assert_includes response.body, "revenue_yen"
    assert_includes response.body, "未接続 / データ不足"
    assert_includes response.body, "収益サマリー"
    assert_includes response.body, "今月売上"
    assert_includes response.body, "今月費用"
    assert_includes response.body, "今月利益"
    assert_includes response.body, "累計利益"
    assert_includes response.body, "代理指標サマリー"
    assert_includes response.body, "直近7日 proxy_score"
    assert_includes response.body, "直近30日 proxy_score"
    assert_includes response.body, "今月 proxy_score"
    assert_includes response.body, "累計 proxy_score"
    assert_includes response.body, "proxy_score重み"
    assert_includes response.body, "confidence_score"
    assert_includes response.body, "Execution Profile"
    assert_includes response.body, "Codex対象プロジェクト"
    assert_includes response.body, "Integration Health"
    assert_includes response.body, "Health Score"
    assert_includes response.body, "GSC"
    assert_includes response.body, "GA4"
    assert_includes response.body, "Business Playbook"
    assert_includes response.body, "Data Source Cost"
    assert_includes response.body, "Analysis Sources"
    assert_includes response.body, "順位急落を確認するためSERP分析を推奨"
    assert_includes response.body, "SERP分析コスト"
    assert_includes response.body, "予想コスト"
    assert_includes response.body, "未紐付け"
    assert_includes response.body, "Data Source紐付けを編集"
    assert_includes response.body, "紐付け設定"
    assert_includes response.body, "CODEX"
  end

  test "should get edit" do
    get edit_business_url(@business)
    assert_response :success
    assert_includes response.body, "Data Source紐付け詳細"
    assert_includes response.body, "AICOO全体設定を使う"
    assert_includes response.body, "Execution mode override"
    assert_includes response.body, "Budget override"
    assert_includes response.body, "Property / Target"
    assert_includes response.body, "Credential参照"
    assert_includes response.body, "GSC site_url"
    assert_includes response.body, "customer_id"
    assert_includes response.body, "Test connection"
    assert_includes response.body, "CODEX"
  end

  test "updates business data source connection settings" do
    DataSourceCostProfile.ensure_defaults!

    patch update_data_source_settings_business_url(@business), params: {
      business_data_source_settings: {
        "ga4" => {
          enabled: "1",
          connection_status: "linked",
          property_identifier: "properties/536889590",
          external_account_id: "ga-account-1",
          endpoint_url: "https://analytics.google.com/",
          credential_reference: "AICOO共通Google認証",
          connection_fields: { property_id: "properties/536889590" },
          source_binding: { use_global: "0", execution_mode: "smart", monthly_budget_yen: "1200" },
          notes: "GA4 production"
        }
      }
    }

    setting = @business.business_data_source_settings.find_by!(source_key: "ga4")
    assert_redirected_to edit_business_url(@business, anchor: "data-source-link-settings")
    assert setting.enabled?
    assert_equal "linked", setting.connection_status
    assert_equal "properties/536889590", setting.property_identifier
    assert_equal "properties/536889590", setting.connection_field_value("property_id")
    assert_equal "0", setting.metadata.dig("source_binding", "use_global")
    assert_equal "smart", setting.metadata.dig("source_binding", "execution_mode")
    assert_equal "1200", setting.metadata.dig("source_binding", "monthly_budget_yen")
    assert_equal "AICOO共通Google認証", setting.credential_reference
    assert setting.last_connected_at.present?
  end

  test "should update business" do
    patch business_url(@business), params: {
      business: {
        description: @business.description,
        gsc_site_url: "sc-domain:suelog.jp",
        name: @business.name,
        status: @business.status,
        project_key: "suelog",
        local_project_path: "/Users/example/suelog",
        repository_name: "suelog-app"
      }
    }
    assert_redirected_to business_url(@business)
    assert_equal "sc-domain:suelog.jp", @business.reload.gsc_site_url
    assert_equal "suelog", @business.project_key
    assert_equal "/Users/example/suelog", @business.local_project_path
    assert_equal "suelog-app", @business.repository_name
  end

  test "should destroy business" do
    assert_difference("Business.count", -1) do
      delete business_url(@business)
    end

    assert_redirected_to businesses_url
  end
end
