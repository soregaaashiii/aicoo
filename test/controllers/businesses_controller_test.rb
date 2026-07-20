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
    assert_includes response.body, "Google設定"
    assert_includes response.body, "Revenue 7日 / 30日"
    assert_includes response.body, "Data Source Cost"
    assert_includes response.body, "Pending Actions"
    assert_includes response.body, "Warning"
    assert_includes response.body, "Analytics"
    assert_includes response.body, "Execution Profile"
    assert_includes response.body, "Auto Revision"
    assert_includes response.body, "Lifecycle"
    assert_includes response.body, "missing"
    assert_includes response.body, "＋ 新しい事業"
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

  test "index does not repair or publish new businesses as a side effect" do
    repairer = ->(**) { raise "ApprovedNewBusinessCandidateRepairer must not run from businesses#index" }
    publisher = ->(**) { raise "AutoNewBusinessPublisher must not run from businesses#index" }
    candidate = ActionCandidate.create!(
      business: @business,
      title: "GETで更新されない候補",
      status: "idea",
      action_type: "seo_improvement",
      generation_source: "business_analyzer"
    )
    original_updated_at = candidate.updated_at

    Aicoo::ApprovedNewBusinessCandidateRepairer.stub(:call, repairer) do
      Aicoo::Serp::AutoNewBusinessPublisher.stub(:call, publisher) do
        assert_no_difference([ "Business.count", "AicooLabLandingPage.count", "ActionCandidate.count", "AicooPipelineRun.count" ]) do
          get businesses_url
        end
      end
    end

    assert_response :success
    assert_equal original_updated_at.to_i, candidate.reload.updated_at.to_i
    assert_not_includes response.body, "Business化しました"
    assert_not_includes response.body, "新規事業を作成"
    assert_not_includes response.body, "LPを"
  end

  test "index remains read only across repeated reloads" do
    before_counts = {
      businesses: Business.count,
      lab_lps: AicooLabLandingPage.count,
      candidates: ActionCandidate.count,
      pipelines: AicooPipelineRun.count
    }

    2.times do
      get businesses_url
      assert_response :success
    end

    assert_equal before_counts[:businesses], Business.count
    assert_equal before_counts[:lab_lps], AicooLabLandingPage.count
    assert_equal before_counts[:candidates], ActionCandidate.count
    assert_equal before_counts[:pipelines], AicooPipelineRun.count
  end

  test "index shows serp new business candidate tab" do
    ActionCandidate.create!(
      business: @business,
      title: "SERP候補タブの新規事業",
      description: "SERPで見つけた新規事業候補",
      action_type: "new_business",
      generation_source: "serp",
      department: "new_business",
      status: "idea",
      metadata: {
        "candidate_kind" => "new_business",
        "source_query" => "新規 SaaS アイデア"
      },
      immediate_value_yen: 30_000,
      success_probability: 0.4
    )

    get businesses_url(tab: "serp_candidates")

    assert_response :success
    assert_includes response.body, "SERP新規事業候補"
    assert_includes response.body, "SERP候補タブの新規事業"
    assert_includes response.body, "事業/LP作成済み"
    assert_includes response.body, "事業を見る"
    assert_includes response.body, "LPを見る"
  end

  test "approving serp new business candidate from business list creates visible business" do
    candidate = ActionCandidate.create!(
      business: @business,
      title: "SERP承認で作るBusiness",
      description: "SERP承認からBusiness化",
      action_type: "new_business",
      generation_source: "serp",
      department: "new_business",
      status: "idea",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "SERP承認Business",
        "source_query" => "SERP 新規事業"
      },
      immediate_value_yen: 30_000,
      success_probability: 0.4
    )

    assert_difference("Business.real_businesses.count", 1) do
      patch approve_action_candidate_url(candidate)
    end

    business = Business.real_businesses.find_by!(name: "SERP承認Business")
    assert_redirected_to business_url(business)
    assert_equal business, candidate.reload.business
    assert_equal "approved", candidate.status
  end

  test "should get new" do
    get new_business_url
    assert_response :success
    assert_includes response.body, "アイデアから作る"
    assert_includes response.body, "プロトタイプを登録する"
    assert_includes response.body, "公開済みサービスを登録する"
    assert_not_includes response.body, "SERP新規事業候補"
  end

  test "registers an idea through business registration v2" do
    assert_difference("Business.count", 1) do
      post businesses_url, params: {
        registration_mode: "idea",
        registration: {
          name: "AI電話受付",
          description: "営業代行会社向けのAI電話受付"
        }
      }
    end

    business = Business.order(:id).last
    assert_redirected_to business_url(business)
    assert_equal "business_registration_v2", business.source
    assert business.action_candidates.exists?(generation_source: "business_registration")
  end

  test "registers a github prototype through business registration v2" do
    assert_difference([ "Business.count", "BusinessPrototype.count" ], 1) do
      post businesses_url, params: {
        registration_mode: "prototype",
        registration: {
          name: "GitHub Prototype",
          prototype_type: "github",
          prototype_location: "https://github.com/example/prototype"
        }
      }
    end

    business = Business.order(:id).last
    assert_redirected_to business_url(business)
    assert_equal "github", business.business_prototypes.first.prototype_type
  end

  test "registers a published service from its url" do
    assert_difference([ "Business.count", "BusinessPrototype.count" ], 1) do
      post businesses_url, params: {
        registration_mode: "published_service",
        registration: { prototype_location: "https://published.example.com" }
      }
    end

    business = Business.order(:id).last
    assert_redirected_to business_url(business)
    assert_equal "published.example.com", business.name
    assert_equal "production", business.lifecycle_stage
  end

  test "should create business" do
    assert_difference("Business.count") do
      post businesses_url, params: { business: { description: @business.description, name: "新規事業探索", status: @business.status, lifecycle_stage: "idea" } }
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
    ActionCandidate.create!(
      business: @business,
      title: "AI改善提案テスト",
      status: "approved",
      action_type: "seo_improvement",
      immediate_value_yen: 12_000,
      success_probability: 0.8,
      expected_hours: 1,
      evaluation_reason: "CTRが低いためSEOタイトル改善を推奨"
    )
    @business.business_services.create!(
      name: "吸えログMVP",
      domain: "suelog-mvp.example.com",
      status: "live"
    )
    experiment = AicooLabExperiment.create!(
      title: "吸えログLP",
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "running",
      approval_status: "approved"
    )
    experiment.create_aicoo_lab_landing_page!(
      business: @business,
      headline: "吸えログ公開LP",
      subheadline: "喫煙できる店を探す",
      body: "公開LP本文",
      cta_text: "登録する",
      status: "published",
      public_status: "published",
      published_slug: "suelog-visible-lp",
      published_at: Time.current
    )
    @business.create_business_execution_profile!(
      production_url: "https://suelog.jp",
      repository_name: "suelog",
      repository_type: "rails",
      repository_path: "/apps/suelog",
      github_repository: "kawamura/suelog",
      test_command: "bin/rails test",
      deploy_command: "bin/deploy"
    )

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "公開確認URL"
    assert_includes response.body, "https://suelog-mvp.example.com"
    assert_includes response.body, "/lp/suelog-visible-lp"
    assert_includes response.body, "https://suelog.jp"
    assert_includes response.body, "Business Analytics Dashboard"
    assert_includes response.body, "事業ホーム"
    assert_includes response.body, "現在フェーズ"
    assert_includes response.body, "運用負荷"
    assert_includes response.body, "Resource Status"
    assert_includes response.body, "Attention Score"
    assert_includes response.body, "LP状況"
    assert_includes response.body, "Service状況"
    assert_includes response.body, "初回設定ウィザード"
    assert_includes response.body, "Business &gt;"
    assert_includes response.body, "概要"
    assert_includes response.body, "Google"
    assert_includes response.body, "SERP"
    assert_includes response.body, "LP"
    assert_includes response.body, "Service"
    assert_includes response.body, "Timeline"
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
    assert_includes response.body, "未設定（未設定）"
    assert_includes response.body, "Data Source紐付けを編集"
    assert_includes response.body, "紐付け設定"
    assert_includes response.body, "CODEX"
    assert_includes response.body, "公開LP管理"
    assert_includes response.body, "LPを新規作成"
    assert_includes response.body, "MVP Ready Check"
    assert_includes response.body, "Business Timeline"
    assert_includes response.body, "Source Connections"
    assert_includes response.body, "Improvement History"
    assert_includes response.body, "LP検証後の実サービス"
    assert_includes response.body, "Production Ready Check"
    assert_includes response.body, "Scaling評価"
    assert_includes response.body, "Daily Run一覧"
    assert_includes response.body, "自動改訂"
    assert_includes response.body, "Manual"
    assert_includes response.body, "AI改善提案"
    assert_includes response.body, "AI改善提案テスト"
    assert_includes response.body, "Codex用プロンプト作成"
    assert_includes response.body, "このBusinessの送信待ちTask"
  end

  test "show does not create pipeline or auto link defaults" do
    linker = ->(*) { raise "BusinessGoogleDefaultLinker must not run from businesses#show" }

    Aicoo::BusinessGoogleDefaultLinker.stub(:call, linker) do
      assert_no_difference([ "Business.count", "AicooLabLandingPage.count", "ActionCandidate.count", "AicooPipelineRun.count", "PipelineRecoveryLog.count" ]) do
        get business_url(@business)
      end
    end

    assert_response :success
  end

  test "business google section shows reauthentication actions" do
    credential = AicooGoogleCredential.create!(
      name: "AICOO共通Google認証",
      client_id: "client",
      client_secret: "secret",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "Google再認証"
    assert_includes response.body, "Business別Google設定"
    assert_includes response.body, "GA4を再認証"
    assert_includes response.body, "GSCを再認証"
    assert_includes response.body, admin_analytics_oauth_connect_path(
      google_credential_id: credential.id,
      business_id: @business.id,
      business_name: @business.name,
      source: "ga4"
    ).gsub("&", "&amp;")
  end

  test "shows business google settings page" do
    credential = AicooGoogleCredential.create!(
      name: "吸えログGoogle認証",
      client_id: "client",
      client_secret: "secret",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )
    AicooAnalyticsSite.create!(
      business: @business,
      name: @business.name,
      public_url: "https://suelog.jp",
      domain: "suelog.jp",
      gsc_site_url: "sc-domain:suelog.jp",
      ga4_property_id: "536889590",
      authentication_mode: "shared"
    )

    get google_settings_business_url(@business)

    assert_response :success
    assert_includes response.body, "#{@business.name} のGoogle連携"
    assert_includes response.body, "ID: <strong>#{@business.id}</strong>"
    assert_includes response.body, "Google Credential"
    assert_includes response.body, "GA4 Property ID"
    assert_includes response.body, "GSC Site URL"
    assert_includes response.body, "536889590"
    assert_includes response.body, "sc-domain:suelog.jp"
    assert_includes response.body, "全体設定を使用"
    assert_includes response.body, "GA4だけテスト取得"
    assert_includes response.body, "GSCだけ再取得"
    assert_includes response.body, "GA4/GSCまとめて再取得"
    assert_includes response.body, credential.name
  end

  test "connection status labels match across business screens when global settings are usable" do
    AicooGoogleCredential.create!(
      name: "AICOO共通Google認証",
      client_id: "client",
      client_secret: "secret",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )
    DataSourceCostProfile.ensure_defaults!
    DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "serper-key")

    get businesses_url
    assert_response :success
    assert_includes response.body, "GA4 設定済み（全体設定を使用）"
    assert_includes response.body, "GSC 設定済み（全体設定を使用）"
    assert_includes response.body, "SERP 設定済み（全体設定を使用）"

    get business_url(@business)
    assert_response :success
    assert_includes response.body, "GA4</span>\n          <strong>設定済み（全体設定を使用）</strong>"
    assert_includes response.body, "GSC</span>\n          <strong>設定済み（全体設定を使用）</strong>"
    assert_includes response.body, "SERP</span>\n          <strong>設定済み（全体設定を使用）</strong>"

    get google_settings_business_url(@business)
    assert_response :success
    assert_includes response.body, "GA4接続</span>\n          <strong>設定済み（全体設定を使用）</strong>"
    assert_includes response.body, "GSC接続</span>\n          <strong>設定済み（全体設定を使用）</strong>"
  end

  test "updates business google settings and syncs analytics settings" do
    credential = AicooGoogleCredential.create!(
      name: "吸えログGoogle認証",
      client_id: "client",
      client_secret: "secret",
      refresh_token: "refresh-token",
      connected_at: Time.current
    )

    patch google_settings_business_url(@business), params: {
      google_settings: {
        google_credential_id: credential.id,
        ga4_enabled: "1",
        ga4_property_id: "536889590",
        gsc_enabled: "1",
        gsc_site_url: "sc-domain:suelog.jp"
      }
    }

    assert_redirected_to google_settings_business_url(@business)
    ga4_setting = @business.business_data_source_settings.find_by!(source_key: "ga4")
    gsc_setting = @business.business_data_source_settings.find_by!(source_key: "gsc")
    assert_equal "536889590", ga4_setting.connection_field_value("property_id")
    assert_equal "sc-domain:suelog.jp", gsc_setting.connection_field_value("site_url")
    assert_equal credential.id, ga4_setting.metadata["google_credential_id"]
    assert_equal credential.id, gsc_setting.metadata["google_credential_id"]
    assert_equal "0", ga4_setting.metadata.dig("source_binding", "use_global")
    assert_equal "0", gsc_setting.metadata.dig("source_binding", "use_global")
    assert_equal "linked", ga4_setting.connection_status
    assert_equal "linked", gsc_setting.connection_status

    site = AicooAnalyticsSite.where(business: @business).recent.first
    assert_equal "536889590", site.ga4_property_id
    assert_equal "sc-domain:suelog.jp", site.gsc_site_url
    assert_equal credential, site.ga4_setting.google_credential
    assert_equal credential, site.gsc_setting.google_credential
  end

  test "business index shows resource status" do
    @business.update!(resource_status: "watch", next_review_on: Date.current + 30.days)

    get businesses_url

    assert_response :success
    assert_includes response.body, "Resource"
    assert_includes response.body, "Watch"
    assert_includes response.body, "次回"
  end

  test "updates resource status with owner approval log" do
    assert_difference -> { BusinessActivityLog.where(activity_type: "resource_status_changed").count }, 1 do
      patch update_resource_status_business_url(@business), params: {
        resource_status: "watch",
        reason: "安定しているためWatchへ移行"
      }
    end

    assert_redirected_to business_url(@business, anchor: "business-resource")
    assert_equal "watch", @business.reload.resource_status
    assert_equal "安定しているためWatchへ移行", @business.resource_status_reason
    assert_match(/運用状態をwatchへ変更しました/, flash[:notice])
  end

  test "show displays lp evaluation summary and mvp promotion button for promising lp" do
    @business.update!(created_by_aicoo: true, lifecycle_stage: "lp_validation")
    landing_page = create_promising_landing_page(@business)
    landing_page.aicoo_lab_landing_page_events.create!(event_type: "view", occurred_at: Time.current)
    3.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click", occurred_at: Time.current) }
    landing_page.aicoo_lab_signups.create!(email: "business-show-mvp@example.com")

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "MVP Ready Check"
    assert_includes response.body, "strong"
    assert_includes response.body, "MVP開発へ進める"
  end

  test "promote to mvp creates service and auto revision task" do
    @business.update!(created_by_aicoo: true, lifecycle_stage: "lp_validation")
    landing_page = create_promising_landing_page(@business, slug: "promote-controller-lp")
    3.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click", occurred_at: Time.current) }

    assert_difference -> { BusinessService.count }, 1 do
      assert_difference -> { AutoRevisionTask.count }, 1 do
        post promote_to_mvp_business_url(@business), params: { landing_page_id: landing_page.id }
      end
    end

    assert_redirected_to business_url(@business, anchor: "business-services")
    assert_equal "mvp", @business.reload.lifecycle_stage
    assert_match(/MVP開発へ進めました/, flash[:notice])
  end

  test "show displays mvp evaluation and production promotion button" do
    @business.update!(created_by_aicoo: true, lifecycle_stage: "mvp")
    service = @business.business_services.create!(
      name: "Controller MVP",
      status: "live",
      url: "https://controller.example.com",
      stripe_account: "acct_test",
      metadata: { registrations: 10, active_users: 6, paid_users: 2, retention_rate: "0.6", user_feedback: "使いたい" }
    )
    @business.revenue_events.create!(event_type: "revenue", amount: 20_000, occurred_on: Date.current)

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "Production Ready Check"
    assert_includes response.body, service.name
    assert_includes response.body, "本番運用へ進める"
  end

  test "promote to production creates auto revision task" do
    @business.update!(created_by_aicoo: true, lifecycle_stage: "mvp")
    service = @business.business_services.create!(
      name: "Promote Production MVP",
      status: "live",
      url: "https://production.example.com",
      stripe_account: "acct_test",
      metadata: { registrations: 10, active_users: 6, paid_users: 2, retention_rate: "0.6", user_feedback: "良い" }
    )
    @business.revenue_events.create!(event_type: "revenue", amount: 20_000, occurred_on: Date.current)

    assert_difference -> { AutoRevisionTask.count }, 1 do
      post promote_to_production_business_url(@business), params: { business_service_id: service.id }
    end

    assert_redirected_to business_url(@business, anchor: "business-services")
    assert_equal "production", @business.reload.lifecycle_stage
    assert_equal "production", service.reload.status
    assert_match(/本番運用へ進めました/, flash[:notice])
  end

  test "show displays scaling evaluation and promotion button" do
    @business.update!(created_by_aicoo: true, lifecycle_stage: "production", status: "launched", launched: true)
    @business.business_services.create!(
      name: "Scaling Controller Service",
      status: "production",
      metadata: {
        paid_users: 6,
        active_users: 15,
        registrations: 20,
        retention_rate: "0.65",
        cac_hypothesis_yen: 7_000,
        ltv_hypothesis_yen: 70_000,
        primary_channel: "SEO"
      }
    )
    @business.revenue_events.create!(event_type: "revenue", amount: 120_000, occurred_on: Date.current)
    @business.revenue_events.create!(event_type: "expense", amount: 10_000, occurred_on: Date.current)
    @business.business_metric_dailies.create!(recorded_on: Date.current, sessions: 100, conversions: 6, impressions: 1_000)

    get business_url(@business)

    assert_response :success
    assert_includes response.body, "Scaling評価"
    assert_includes response.body, "Scalingへ進める"
    assert_includes response.body, "Scaling Ready Check"
  end

  test "promote to scaling creates auto revision task" do
    @business.update!(created_by_aicoo: true, lifecycle_stage: "production", status: "launched", launched: true)
    @business.business_services.create!(
      name: "Promote Scaling Service",
      status: "production",
      metadata: {
        paid_users: 6,
        active_users: 15,
        registrations: 20,
        retention_rate: "0.65",
        cac_hypothesis_yen: 7_000,
        ltv_hypothesis_yen: 70_000,
        primary_channel: "SEO"
      }
    )
    @business.revenue_events.create!(event_type: "revenue", amount: 120_000, occurred_on: Date.current)
    @business.revenue_events.create!(event_type: "expense", amount: 10_000, occurred_on: Date.current)
    @business.business_metric_dailies.create!(recorded_on: Date.current, sessions: 100, conversions: 6, impressions: 1_000)

    assert_difference -> { AutoRevisionTask.count }, 1 do
      post promote_to_scaling_business_url(@business)
    end

    assert_redirected_to business_url(@business, anchor: "business-scaling")
    assert_equal "scaling", @business.reload.lifecycle_stage
    assert_match(/Scalingへ進めました/, flash[:notice])
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
    assert_equal "GSCのGoogle Credentialを確認してください。Business別Google設定でCredential選択または再認証が必要です。", flash[:alert]
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
    assert_includes response.body, "CEOモード"
    assert_includes response.body, "事業一覧"
    assert_not_includes response.body, "システムモード</strong>\n          <span>目的から探す</span>"
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
        auto_revision_mode: "automatic",
        auto_deploy_mode: "approval"
      }
    }
    assert_redirected_to return_to
    assert_equal "sc-domain:suelog.jp", @business.reload.gsc_site_url
    assert_equal "suelog", @business.project_key
    assert_equal "/Users/example/suelog", @business.local_project_path
    assert_equal "suelog-app", @business.repository_name
    assert_equal "automatic", @business.auto_revision_mode
    assert_equal "approval", @business.auto_deploy_mode
  end

  test "soft deletes business instead of destroying related data" do
    candidate = ActionCandidate.create!(
      business: @business,
      title: "削除後も保持する候補",
      status: "approved",
      action_type: "seo_improvement",
      generation_source: "business_analyzer"
    )

    assert_no_difference("Business.count") do
      delete business_url(@business), params: { deletion_reason: "SERP誤生成" }
    end

    assert_redirected_to businesses_url
    @business.reload
    assert @business.deleted?
    assert_equal "SERP誤生成", @business.deletion_reason
    assert_not @business.daily_run_enabled?
    assert_not @business.serp_enabled?
    assert_equal "manual", @business.auto_revision_mode
    assert ActionCandidate.exists?(candidate.id)
    assert_not_includes Business.real_businesses, @business
  end

  test "soft delete marks serp new business candidate as do not recreate" do
    business = Business.create!(name: "SERP誤生成テスト", status: "exploring", source: "serp")
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "SERP誤生成テスト",
      status: "done",
      action_type: "new_business",
      department: "new_business",
      generation_source: "serp",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "SERP誤生成テスト"
      }
    )
    candidate.update_columns(business_id: business.id)

    delete business_url(business), params: { deletion_reason: "SERP誤生成" }

    assert_redirected_to businesses_url
    candidate.reload
    assert_equal true, candidate.metadata["do_not_recreate"]
    assert_equal true, candidate.metadata["auto_republish_blocked"]
    assert_equal business.id, candidate.metadata["deleted_business_id"]
    assert_equal "SERP誤生成", candidate.metadata["deletion_reason"]
  end

  test "deleted businesses are shown on deleted list and can be restored" do
    @business.soft_delete!(reason: "既存事業との重複", actor: "owner", source: "test")

    get deleted_businesses_url

    assert_response :success
    assert_includes response.body, @business.name
    assert_includes response.body, "既存事業との重複"
    assert_includes response.body, "復元"
    assert_includes response.body, "完全削除"

    patch restore_business_url(@business)

    assert_redirected_to business_url(@business)
    assert_not @business.reload.deleted?
    assert_includes Business.real_businesses, @business
  end

  test "bulk delete selected businesses" do
    business = Business.create!(name: "一括削除対象", status: "exploring")

    repairer = ->(**) { raise "ApprovedNewBusinessCandidateRepairer must not run from bulk_delete" }
    publisher = ->(**) { raise "AutoNewBusinessPublisher must not run from bulk_delete" }

    Aicoo::ApprovedNewBusinessCandidateRepairer.stub(:call, repairer) do
      Aicoo::Serp::AutoNewBusinessPublisher.stub(:call, publisher) do
        assert_no_difference([ "Business.count", "AicooLabLandingPage.count", "ActionCandidate.count", "SerpRun.count", "AicooPipelineRun.count" ]) do
          patch bulk_delete_businesses_url, params: {
            business_ids: [ @business.id, business.id ],
            deletion_reason: "SERP誤生成"
          }
        end
      end
    end

    assert_redirected_to businesses_url
    assert @business.reload.deleted?
    assert business.reload.deleted?
    assert_equal "SERP誤生成", business.deletion_reason
    assert_equal "2件の事業を削除しました。", flash[:notice]
    assert_not_match(/Business化|新規事業を作成|LPを.*公開|承認しました|Pipelineを開始/, flash[:notice].to_s)
  end

  test "bulk delete redirect does not recreate deleted business or landing page" do
    business = Business.create!(name: "削除後再生成禁止", status: "exploring", source: "serp")
    candidate = ActionCandidate.create!(
      business: business,
      title: "削除後再生成禁止",
      status: "done",
      action_type: "new_business",
      department: "new_business",
      generation_source: "serp",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "削除後再生成禁止"
      }
    )

    assert_no_difference([ "Business.count", "AicooLabLandingPage.count" ]) do
      patch bulk_delete_businesses_url, params: {
        business_ids: [ business.id ],
        deletion_reason: "SERP誤生成"
      }
      follow_redirect!
    end

    assert_response :success
    assert business.reload.deleted?
    assert_equal true, candidate.reload.metadata["do_not_recreate"]
    assert_equal 0, Business.real_businesses.where(name: "削除後再生成禁止").count
  end

  test "business index bulk delete form posts only to bulk delete route" do
    get businesses_url

    assert_response :success
    assert_select "form#bulk-business-delete-form[action='#{bulk_delete_businesses_path}'][method='post']", count: 1 do
      assert_select "input[name='_method'][value='patch']", count: 1
      assert_select "input[name='business_ids[]']", minimum: 1
      assert_select "input[type='submit'][value='選択した事業を削除'][form='bulk-business-delete-form']", count: 1
    end
    form_html = Nokogiri::HTML(response.body).at_css("form#bulk-business-delete-form").to_html
    assert_no_match(%r{owner/new_business_pipeline|approve|create_lp|publish|pipeline_e2e_check/repair}, form_html)
  end

  test "permanent delete requires soft deleted business name confirmation" do
    business = Business.create!(name: "完全削除対象", status: "exploring")
    business.soft_delete!(reason: "誤登録", actor: "owner", source: "test")

    assert_no_difference("Business.count") do
      delete permanently_destroy_business_url(business), params: { confirmation_name: "wrong" }
    end
    assert_redirected_to deleted_businesses_url

    assert_difference("Business.count", -1) do
      delete permanently_destroy_business_url(business), params: { confirmation_name: "完全削除対象" }
    end
    assert_redirected_to deleted_businesses_url
  end

  private

  def create_promising_landing_page(business, slug: "business-controller-mvp-lp")
    experiment = AicooLabExperiment.create!(
      title: slug,
      experiment_type: "lp",
      acquisition_channel: "seo",
      status: "running",
      approval_status: "approved",
      assumed_price_yen: 1_980
    )
    experiment.create_aicoo_lab_landing_page!(
      business:,
      headline: "MVP昇格テストLP",
      subheadline: "対象ユーザーが明確なサービス案",
      body: "課題を整理し、最小機能で解決するMVP候補です。",
      cta_text: "事前登録する",
      status: "published",
      public_status: "published",
      published_slug: slug,
      published_at: Time.current,
      assumed_price_yen: 1_980
    )
  end
end
