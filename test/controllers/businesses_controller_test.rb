require "test_helper"

class BusinessesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    @business = businesses(:suelog)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "should get index" do
    Business.create!(
      name: "AICOO Analytics Import",
      description: "system import folder",
      status: "launched"
    )

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
    assert_includes response.body, "Auto Revision"
    assert_includes response.body, "missing"
    assert_includes response.body, "Profile作成"
    assert_includes response.body, "CODEX"
    assert_not_includes response.body, "AICOO Analytics Import"
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

  test "index shows aicoo internal codex status without execution profile requirement" do
    @business.update!(created_by_aicoo: true)

    get businesses_url

    assert_response :success
    assert_includes response.body, "AICOO内部"
    assert_includes response.body, "AICOO本体Repository"
  end

  test "index shows published lp idea pipeline business and still hides analytics import business" do
    Business.create!(
      name: "AICOO Analytics Import",
      description: "system import folder",
      status: "launched"
    )
    pipeline_business = Business.create!(
      name: "Pipelineから公開された事業",
      description: "published LP由来",
      status: "launched",
      source: "idea_pipeline",
      idea_id: 12_345,
      created_by_aicoo: true,
      launched: true,
      daily_run_enabled: true,
      serp_enabled: true,
      auto_revision_mode: "manual"
    )
    experiment = AicooLabExperiment.create!(
      title: "Pipeline LP",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "running",
      approval_status: "approved"
    )
    experiment.create_aicoo_lab_landing_page!(
      business: pipeline_business,
      headline: "Pipeline LP",
      subheadline: "公開LP",
      body: "本文",
      cta_text: "登録する",
      status: "published",
      public_status: "published",
      published_slug: "pipeline-business-visible",
      published_at: Time.current
    )

    get businesses_url

    assert_response :success
    assert_includes response.body, "Pipelineから公開された事業"
    assert_not_includes response.body, "AICOO Analytics Import"
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
    assert_includes response.body, "初回設定ウィザード"
    assert_includes response.body, "Business &gt;"
    assert_includes response.body, "概要"
    assert_includes response.body, "Google"
    assert_includes response.body, "SERP"
    assert_includes response.body, "LP"
    assert_includes response.body, "Daily Run"
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
    assert_includes response.body, "公開LP管理"
    assert_includes response.body, "LPを新規作成"
    assert_includes response.body, "Daily Run一覧"
    assert_includes response.body, "自動改訂"
    assert_includes response.body, "Manual"
  end

  test "show treats global google credential as connected and exposes gsc ga4 fetch buttons" do
    credential = AicooGoogleCredential.create!(
      name: "AICOO共通Google認証",
      client_id: "client",
      client_secret: "secret",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )
    site = AicooAnalyticsSite.create!(
      business: @business,
      name: "Suelog",
      public_url: "https://suelog.test",
      domain: "suelog.test",
      gsc_site_url: "sc-domain:suelog.test",
      ga4_property_id: "properties/123",
      authentication_mode: "shared"
    )
    site.gsc_setting.update!(google_credential: credential)
    site.ga4_setting.update!(google_credential: credential)

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "Google API直取得"
    assert_includes response.body, "Google APIから取得"
    assert_includes response.body, "Google紐付けを編集"
    assert_includes response.body, "data-aicoo-submit-lock=\"true\""
    assert_includes response.body, "data-aicoo-loading-label=\"Google API取得中...\""
    assert_includes response.body, "GSC取得"
    assert_includes response.body, "GA4取得"
    assert_includes response.body, "接続済み"
    assert_includes response.body, "実行履歴"
    refute_includes response.body, "GSC未接続"
    refute_includes response.body, "GA4未接続"
  end

  test "show displays long running operation status and links google api history to system" do
    GoogleApiImportRun.create!(
      business: @business,
      status: "running",
      source_types: %w[gsc ga4],
      fetched_days: 3,
      started_at: 5.minutes.ago
    )
    GoogleApiImportRun.create!(
      business: @business,
      status: "success",
      source_types: %w[gsc],
      fetched_days: 1,
      started_at: 30.minutes.ago,
      finished_at: 29.minutes.ago,
      duration_seconds: 60,
      updated_metric_count: 2
    )
    GoogleApiImportRun.create!(
      business: @business,
      status: "failed",
      source_types: %w[ga4],
      fetched_days: 1,
      started_at: 45.minutes.ago,
      finished_at: 44.minutes.ago,
      error_message: "Refresh Tokenがありません"
    )

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "実行中の処理があります"
    assert_includes response.body, "Google API取得中"
    assert_includes response.body, "data-aicoo-auto-refresh=\"5000\""
    assert_includes response.body, "実行履歴"
    assert_not_includes response.body, "Refresh Tokenがありません"
    assert_not_includes response.body, "直近実行履歴"
  end

  test "imports google api metrics into business metric daily from business dashboard" do
    credential = AicooGoogleCredential.create!(
      name: "AICOO共通Google認証",
      google_cloud_project_id: "aicoo-500805",
      client_id: "705900000000-new.apps.googleusercontent.com",
      client_secret: "secret",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )

    assert_difference("GoogleApiImportRun.count", 1) do
      assert_enqueued_with(job: AicooAnalytics::BusinessGoogleApiImportJob) do
        post import_google_api_business_url(@business)
      end
    end

    run = GoogleApiImportRun.last
    assert_equal @business, run.business
    assert_equal "queued", run.status
    assert_equal credential.id, run.metadata.dig("google_credential_at_enqueue", "record_id")
    assert_equal "705900000000-new.apps.googleusercontent.com", run.metadata.dig("google_credential_at_enqueue", "client_id")
    assert_equal "aicoo-500805", run.metadata.dig("google_credential_at_enqueue", "google_cloud_project_id")
    assert_redirected_to business_url(@business, anchor: "business-google")
    assert_equal "Google API取得を開始しました。BusinessMetricDailyへの反映は完了後に表示されます。", flash[:notice]
  end

  test "does not enqueue google api import from business dashboard when google credential needs reauthentication" do
    AicooGoogleCredential.create!(
      name: "AICOO共通Google認証",
      client_id: "new-client",
      client_secret: "secret",
      refresh_token: nil
    )

    assert_no_difference("GoogleApiImportRun.count") do
      assert_no_enqueued_jobs do
        post import_google_api_business_url(@business)
      end
    end

    assert_redirected_to business_url(@business, anchor: "business-google")
    assert_equal "Google OAuth Clientが変更されています。Google認証画面で再認証してください。", flash[:alert]
  end

  test "should get edit" do
    get edit_business_url(@business)
    assert_response :success
    assert_includes response.body, "Business個別紐付け設定"
    assert_includes response.body, "Business &gt;"
    assert_includes response.body, "概要"
    assert_includes response.body, "Google"
    assert_includes response.body, "SERP"
    assert_includes response.body, "LP"
    assert_includes response.body, "Daily Run"
    assert_includes response.body, "AICOO全体設定を使う"
    assert_includes response.body, "Execution mode override"
    assert_includes response.body, "Budget override"
    assert_includes response.body, "Property / Target"
    assert_includes response.body, "Credential参照"
    assert_includes response.body, "GA4 Propertyを選択"
    assert_includes response.body, "GSC Siteを選択"
    assert_includes response.body, "状態は保存後に自動判定されます。"
    assert_includes response.body, "customer_id"
    assert_includes response.body, "Test connection"
    assert_includes response.body, "CODEX"
  end

  test "updates business data source connection settings" do
    DataSourceCostProfile.ensure_defaults!
    AicooGoogleCredential.create!(
      name: "AICOO共通Google認証",
      client_id: "client",
      client_secret: "secret",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )

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
    assert_equal "properties/536889590", AicooAnalyticsSite.where(business: @business).recent.first.ga4_property_id
  end

  test "updates business data source connection settings and returns to requested tab" do
    DataSourceCostProfile.ensure_defaults!
    return_to = business_path(@business, anchor: "business-google")

    patch update_data_source_settings_business_url(@business), params: {
      return_to:,
      business_data_source_settings: {
        "gsc" => {
          enabled: "1",
          connection_status: "linked",
          property_identifier: "sc-domain:suelog.jp",
          external_account_id: "",
          endpoint_url: "",
          credential_reference: "AICOO共通Google認証",
          connection_fields: { site_url: "sc-domain:suelog.jp" },
          source_binding: { use_global: "1", execution_mode: "", monthly_budget_yen: "" },
          notes: ""
        }
      }
    }

    assert_redirected_to return_to
  end

  test "should update business" do
    return_to = business_path(@business, anchor: "business-settings")

    patch business_url(@business), params: {
      return_to:,
      business: {
        description: @business.description,
        gsc_site_url: "sc-domain:suelog.jp",
        name: @business.name,
        status: @business.status,
        project_key: "suelog",
        local_project_path: "/Users/example/suelog",
        repository_name: "suelog-app",
        auto_revision_mode: "automatic"
      }
    }
    assert_redirected_to return_to
    assert_equal "sc-domain:suelog.jp", @business.reload.gsc_site_url
    assert_equal "suelog", @business.project_key
    assert_equal "/Users/example/suelog", @business.local_project_path
    assert_equal "suelog-app", @business.repository_name
    assert_equal "automatic", @business.auto_revision_mode
  end

  test "should destroy business" do
    assert_difference("Business.count", -1) do
      delete business_url(@business)
    end

    assert_redirected_to businesses_url
  end
end
