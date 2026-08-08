require "test_helper"

class BusinessAccessSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = Business.create!(
      name: "外部LP管理テスト事業",
      description: "Service・LP・共通計測の分離テスト",
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

  test "business detail makes landing pages primary and keeps campaigns in developer details" do
    get business_url(@business)

    assert_response :success
    assert_select "#business-access-urls"
    assert_select "#business-service-access-card", text: /Service/
    assert_select "#business-lp-access-card", text: /LP/
    assert_select "#business-measurement-access-card", text: /計測/
    assert_select "#business-lp-planner-card", text: /改善Planner/
    assert_select "#business-lp-analyzer-dashboard", text: /利益実績/
    assert_select "summary", text: "+ Service追加"
    assert_select "#business-lp-access-card summary", text: "＋LP追加", count: 1
    assert_select "summary", text: "＋LP追加", count: 1
    assert_select "#business-lp-access-card a[href='#{new_existing_landing_page_business_access_settings_path(@business)}']",
      text: "既存LPを登録",
      count: 1
    assert_select "details.business-campaign-developer-settings:not([open])" do
      assert_select "summary", text: "開発者向け"
      assert_select "#business-campaign-access-card", text: /Campaign/
      assert_select "summary", text: "+ 内部施策追加"
    end
    assert_select "summary", text: "共通計測を設定"
    assert_select "summary", text: "Cloudflare公開先を選択"
    assert_select "select[name='cloudflare_access[project_name]']"
    assert_select "select[name='cloudflare_access[production_url]']"
    assert_select "input[name='cloudflare_access[api_token]']", count: 0
    assert_select "input[name='cloudflare_access[account_id]']", count: 0
    assert_select "#business-campaign-access-card input[name='measurement_access[ga4_property_id]']", count: 0
    assert_select "#business-campaign-access-card input[name='measurement_access[gsc_site_url]']", count: 0
  end

  test "existing landing page form opens without a get write" do
    statements = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:cached] || payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])

      statements << payload[:sql].to_s
    end

    assert_no_difference [ "BusinessPrototype.count", "BusinessCampaign.count" ] do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get new_existing_landing_page_business_access_settings_url(@business)
      end
    end

    assert_response :success
    assert_empty statements.grep(/\A\s*(?:INSERT|UPDATE|DELETE)/i)
    assert_select "h1", text: "既存LPを登録"
    assert_select "form[action='#{existing_landing_pages_business_access_settings_path(@business)}']" do
      assert_select "input[name='existing_lp[name]'][required]"
      assert_select "input[name='existing_lp[url]'][type='url'][required]"
      assert_select "input[name='existing_lp[repository_url]'][type='url']"
      assert_select "input[type='submit'][value='登録する']"
    end
    assert_includes response.body, "すでに公開済みのLPを、この事業の管理対象に追加します。"
  end

  test "registers an existing landing page and returns to the business lp list" do
    assert_difference -> { @business.business_prototypes.external_landing_pages.count }, 1 do
      post existing_landing_pages_business_access_settings_url(@business), params: {
        existing_lp: {
          name: "VAULT",
          url: "https://example.com/vault/",
          repository_url: "https://github.com/Soregaaashiii/Vault.git"
        }
      }
    end

    landing_page = @business.business_prototypes.external_landing_pages.find_by!(name: "VAULT")
    assert_redirected_to business_url(@business, anchor: "business-lp-access-card")
    assert_equal "https://example.com/vault", landing_page.landing_page_url
    assert_equal "https://github.com/soregaaashiii/vault", landing_page.landing_page_repository_url
    assert_nil @other_business.business_prototypes.external_landing_pages.find_by(name: "VAULT")

    follow_redirect!
    assert_response :success
    assert_select "#external-lp-#{landing_page.id}", text: /VAULT/
    assert_select "#external-lp-#{landing_page.id} a[href='https://github.com/soregaaashiii/vault']"
    assert_select "#external-lp-#{landing_page.id}", text: /登録日時/
    assert_select "body", text: /既存LPを登録しました。/
  end

  test "registers an existing landing page without github" do
    post existing_landing_pages_business_access_settings_url(@business), params: {
      existing_lp: { name: "URLのみ", url: "https://example.com/url-only" }
    }

    assert_redirected_to business_url(@business, anchor: "business-lp-access-card")
    landing_page = @business.business_prototypes.external_landing_pages.find_by!(name: "URLのみ")
    assert_nil landing_page.landing_page_repository_url
  end

  test "shows japanese field errors and does not save invalid or duplicate input" do
    post existing_landing_pages_business_access_settings_url(@business), params: {
      existing_lp: { name: "不正", url: "not-a-url", repository_url: "https://example.com/not-github" }
    }

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /httpまたはhttpsの正しいURL/
    assert_select "[role='alert']", text: /GitHubリポジトリURL/

    Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).register_existing!(
      name: "登録済み",
      url: "https://example.com/duplicate"
    )
    assert_no_difference -> { @business.business_prototypes.external_landing_pages.count } do
      post existing_landing_pages_business_access_settings_url(@business), params: {
        existing_lp: { name: "重複", url: "https://example.com/duplicate/" }
      }
    end

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /この事業に登録済み/
  end

  test "existing landing page registration requires management authentication" do
    previous = {
      "AICOO_ENABLE_BASIC_AUTH" => ENV["AICOO_ENABLE_BASIC_AUTH"],
      "AICOO_BASIC_AUTH_USERNAME" => ENV["AICOO_BASIC_AUTH_USERNAME"],
      "AICOO_BASIC_AUTH_PASSWORD" => ENV["AICOO_BASIC_AUTH_PASSWORD"]
    }
    ENV["AICOO_ENABLE_BASIC_AUTH"] = "true"
    ENV["AICOO_BASIC_AUTH_USERNAME"] = "aicoo-admin"
    ENV["AICOO_BASIC_AUTH_PASSWORD"] = "secret-password"

    assert_no_difference("BusinessPrototype.count") do
      post existing_landing_pages_business_access_settings_url(@business), params: {
        existing_lp: { name: "未認証LP", url: "https://example.com/unauthorized" }
      }
    end
    assert_response :unauthorized
  ensure
    previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "business stores only a selected cloudflare project and domain" do
    DataSourceCostProfile.create!(
      source_key: "cloudflare_pages",
      name: "Cloudflare Pages",
      metadata: {
        "credentials" => { "account_id" => "global-account", "api_token" => "global-token" },
        "cloudflare" => {
          "status" => "connected",
          "projects" => [
            {
              "name" => "aicoo-lp",
              "production_url" => "https://aicoo-lp.pages.dev",
              "domains" => [ "lp.example.com" ]
            }
          ]
        }
      }
    )
    BusinessDataSourceSetting.create!(
      business: @business,
      source_key: "cloudflare_pages",
      metadata: {
        "api_token" => "legacy-business-token",
        "credentials" => { "account_id" => "legacy-account" }
      }
    )

    patch cloudflare_business_access_settings_url(@business), params: {
      cloudflare_access: {
        project_name: "aicoo-lp",
        production_url: "https://lp.example.com"
      }
    }

    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    setting = BusinessDataSourceSetting.find_by!(business: @business, source_key: "cloudflare_pages")
    assert_equal "aicoo-lp", setting.property_identifier
    assert_equal "https://lp.example.com", setting.endpoint_url
    assert_equal "AICOO全体Cloudflare認証", setting.credential_reference
    assert_equal({ "use_global" => "1" }, setting.metadata["source_binding"])
    assert_nil setting.metadata["api_token"]
    assert_nil setting.metadata["account_id"]
    assert_nil setting.metadata["credentials"]
  end

  test "business detail links each landing page to its canonical analyzer detail" do
    campaign = @business.business_campaigns.create!(name: "SEO", campaign_type: "seo", status: "active")
    landing_page = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
      campaign_id: campaign.id,
      name: "計測LP",
      source_type: "public_url",
      url: "https://lp.example.com/analyzer",
      ga4_page_path: "/analyzer",
      public_status: "published"
    )

    get business_url(@business)

    assert_response :success
    assert_select "#external-lp-#{landing_page.id}", count: 1
    assert_select "#external-lp-#{landing_page.id} a[href='#{business_lovable_landing_page_path(@business, landing_page_id: landing_page.id)}']", minimum: 1
    assert_select "#external-lp-#{landing_page.id} form", count: 0

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)

    assert_response :success
    assert_select "#lp-analyzer", text: /Analyzer/
    assert_select "#lp-analyzer", text: /Session/
    assert_select "#lp-learning", text: /Learning/
  end

  test "landing page settings expose only owner managed fields and keep ai managed fields read only" do
    landing_page = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
      name: "AI管理LP",
      source_type: "github",
      repository_url: "https://github.com/example/ai-managed-lp",
      branch: "main",
      url: "https://aicoo-lp.pages.dev/ai-managed/",
      ga4_page_path: "/ai-managed",
      public_status: "testing",
      current_conversion_rate: 0.04,
      improvement_target: "cta_improvement",
      cloudflare_deploy_status: "deploying",
      ab_variant: "B",
      ab_status: "running",
      ab_win_rate: 0.55
    )
    landing_page.update!(metadata: landing_page.metadata.merge(
      "github_commit_sha" => "abc123",
      "pipeline_stage" => "cloudflare_pending",
      "pipeline_stages" => Aicoo::LpIntegration::LandingPagePipelineState.build(
        current: "cloudflare_pending",
        approval_required: false
      )
    ))

    get business_lovable_landing_page_url(@business, landing_page_id: landing_page.id)

    assert_response :success
    assert_select "#lp-settings" do
      assert_select "input[name='lp_access[name]']", count: 1
      assert_select "input[name='lp_access[lovable_project_url]']", count: 1
      assert_select "input[name='lp_access[repository_url]']", count: 1
      assert_select "input[name='lp_access[branch]']", count: 1
      assert_select "input[name='lp_access[cta_destination_url]']", count: 1
      assert_select "input[name='lp_access[url]']", count: 0
      assert_select "input[name='lp_access[ga4_page_path]']", count: 0
      assert_select "[name='lp_access[public_status]']", count: 0
      assert_select "[name='lp_access[current_conversion_rate]']", count: 0
      assert_select "[name='lp_access[improvement_target]']", count: 0
      assert_select "[name='lp_access[cloudflare_deploy_status]']", count: 0
      assert_select "[name='lp_access[ab_win_rate]']", count: 0
      assert_select "[name='lp_access[ab_winner]']", count: 0
      assert_select "form[action='#{publish_landing_page_business_access_settings_path(@business, landing_page_id: landing_page.id)}']", count: 0
      assert_select "form[action='#{landing_page_task_business_access_settings_path(@business, landing_page_id: landing_page.id)}']", count: 0
      assert_select "form[action='#{landing_page_status_business_access_settings_path(@business, landing_page_id: landing_page.id)}']", count: 0
      assert_select "button", text: "公開中にする", count: 0
      assert_select "label", text: "このVariantを勝者にする", count: 0
    end
    assert_select "#lp-analyzer form", count: 0
    assert_select "#lp-learning form", count: 0
    assert_select "#lovable-pipeline-live"
  end

  test "owner setting update preserves analyzer pipeline and publication values" do
    landing_page = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
      name: "保存前LP",
      source_type: "github",
      repository_url: "https://github.com/example/original",
      branch: "develop",
      lovable_project_url: "https://lovable.dev/projects/original",
      url: "https://aicoo-lp.pages.dev/preserved/",
      ga4_page_path: "/preserved",
      public_status: "published",
      current_conversion_rate: 0.08,
      improvement_target: "seo_improvement",
      cloudflare_deploy_status: "deployed",
      ab_variant: "B",
      ab_status: "running",
      ab_win_rate: 0.72
    )
    landing_page.update!(metadata: landing_page.metadata.merge(
      "github_commit_sha" => "preserved-sha",
      "pipeline_stage" => "learning_pending",
      "lovable_generation_run_id" => AicooLabGenerationRun.create!(
        generation_type: "lp_generation",
        status: "succeeded",
        metadata: {
          "pipeline" => "lovable",
          "pipeline_status" => "lovable_handoff_ready",
          "business_id" => @business.id,
          "landing_page_prototype_id" => landing_page.id
        }
      ).id
    ))
    generation_run = AicooLabGenerationRun.find(landing_page.metadata["lovable_generation_run_id"])
    preserved = landing_page.metadata.slice(
      "lp_url",
      "ga4_page_path",
      "lp_public_status",
      "current_conversion_rate",
      "improvement_target",
      "cloudflare_deploy_status",
      "ab_test",
      "github_commit_sha",
      "pipeline_stage"
    )

    patch landing_page_business_access_settings_url(@business), params: {
      lp_access: {
        landing_page_id: landing_page.id,
        name: "設定更新後LP",
        repository_url: "https://github.com/example/updated",
        branch: "main",
        lovable_project_url: "https://lovable.dev/projects/updated",
        cta_destination_url: "https://service.example.com/contact",
        url: "https://malicious.example.com",
        ga4_page_path: "/overwritten",
        public_status: "stopped",
        current_conversion_rate: 0.99,
        improvement_target: "manual",
        cloudflare_deploy_status: "failed",
        ab_win_rate: 1.0
      }
    }

    assert_redirected_to business_lovable_landing_page_url(@business, landing_page_id: landing_page.id, anchor: "lp-settings")
    landing_page.reload
    assert_equal "設定更新後LP", landing_page.landing_page_name
    assert_equal "https://github.com/example/updated", landing_page.landing_page_repository_url
    assert_equal "main", landing_page.landing_page_branch
    assert_equal "https://lovable.dev/projects/updated", landing_page.metadata["lovable_project_url"]
    assert_equal "https://service.example.com/contact", landing_page.metadata["cta_destination_url"]
    assert_equal preserved, landing_page.metadata.slice(*preserved.keys)
    assert_equal "https://github.com/example/updated", generation_run.reload.metadata["lovable_result_repository"]
    assert_equal "main", generation_run.metadata["lovable_result_branch"]
    assert_equal "https://lovable.dev/projects/updated", generation_run.metadata["lovable_project_url"]
    assert_equal "updated", generation_run.metadata["lovable_project_id"]
  end

  test "saving a github repository creates the first version and starts import automatically" do
    campaign = @business.business_campaigns.create!(name: "SEO", campaign_type: "seo", status: "active")
    landing_page = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
      campaign_id: campaign.id,
      name: "自動同期LP",
      source_type: "manual",
      ga4_page_path: "/auto-sync",
      public_status: "testing"
    )

    assert_difference("AicooLabGenerationRun.count", 1) do
      assert_enqueued_jobs 1, only: Aicoo::LovableResultImportJob do
        patch landing_page_business_access_settings_url(@business), params: {
          lp_access: {
            landing_page_id: landing_page.id,
            name: "自動同期LP",
            repository_url: "https://github.com/example/auto-sync-lp",
            branch: "main"
          }
        }
      end
    end

    assert_redirected_to business_lovable_landing_page_url(
      @business,
      landing_page_id: landing_page.id,
      anchor: "lp-settings"
    )
    follow_redirect!
    assert_response :success
    assert_select "#lovable-versions tbody tr", minimum: 1
    assert_select "#lovable-versions", text: /v1/
    assert_select "#lovable-versions", text: /repository_import/
    assert_select "#lovable-versions", text: /Versionはまだありません。/, count: 0
    assert_select "body", text: /GitHub最新版の自動取得を開始しました/
  end

  test "landing page creation asks only for purpose and does not ask for campaign" do
    get business_url(@business)

    assert_response :success
    assert_select "form.lp-creation-form", count: 1 do
      assert_select "select[name='lp_plan[purpose]']"
      Aicoo::LpIntegration::LandingPageStrategyBuilder::PURPOSES.each do |value, label|
        assert_select "option[value='#{value}']", text: label
      end
      assert_select ".lp-creation-core-fields input[name='lp_plan[name]']", count: 0
      assert_select ".lp-creation-core-fields textarea[name='lp_plan[notes]']", count: 0
      assert_select "details.lp-advanced-settings", text: /補足・詳細設定/ do
        assert_select "input[name='lp_plan[name]']", count: 1
        assert_select "textarea[name='lp_plan[notes]']", count: 1
      end
      assert_select "input[name='lp_plan[keywords]']", count: 0
      assert_select "input[name='lp_plan[advanced][keywords]']", count: 1
      assert_select "input[name='lp_plan[campaign_id]']", count: 0
      assert_select "input[type='submit'][value='生成開始']"
    end
  end

  test "landing page generation resolves its campaign from purpose and waits for approval" do
    plan = nil

    assert_no_difference [ "BusinessPrototype.count", "BusinessCampaign.count", "AicooAnalyticsSite.count", "AnalyticsSourceSetting.count" ] do
      assert_difference [ "AicooLabGenerationRun.count", "ActionCandidate.count", "AutoRevisionTask.count" ], 1 do
        post landing_page_plan_business_access_settings_url(@business), params: {
          lp_plan: { purpose: "regional" }
        }
      end
      plan = AicooLabGenerationRun.order(:created_at).last
    end

    assert_redirected_to landing_page_plan_review_business_access_settings_url(@business, plan_id: plan.id)
    follow_redirect!
    assert_response :success
    assert_select "h1, h2", text: /LP生成レビュー/
    assert_select "form[action='#{execute_landing_page_plan_business_access_settings_path(@business, plan_id: plan.id)}'] button", text: "実行"
    assert_select ".lp-pipeline-stage", minimum: 9
    assert_includes response.body, "Lovable、GitHub、Cloudflareへは送信しません"

    assert_difference [
      -> { @business.business_campaigns.count },
      -> { @business.business_prototypes.active.external_landing_pages.count }
    ], 1 do
      post execute_landing_page_plan_business_access_settings_url(@business, plan_id: plan.id)
    end
    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    campaign = @business.business_campaigns.find_by!(name: "Regional")
    assert_equal "seo", campaign.campaign_type
    assert_equal "regional", campaign.metadata.to_h["planner_purpose"]
    assert_equal campaign, @business.business_prototypes.active.external_landing_pages.order(:created_at).last.business_campaign
    assert_equal "waiting_approval", @business.auto_revision_tasks.order(:created_at).last.status
    assert_nil @business.auto_revision_tasks.order(:created_at).last.sent_to_codex_at
  end

  test "business can store multiple campaigns and landing pages belong to a campaign" do
    assert_difference -> { @business.business_campaigns.count }, 2 do
      save_campaign(name: "SEO", campaign_type: "seo")
      save_campaign(name: "Google Ads", campaign_type: "google_ads")
    end

    campaign = @business.business_campaigns.find_by!(name: "Google Ads")
    save_landing_page(name: "広告 A", path: "/ads/a", repository: "https://github.com/example/ads-a", campaign:)
    landing_page = @business.business_prototypes.external_landing_pages.find_by!(name: "広告 A")

    assert_equal campaign, landing_page.business_campaign
    assert_equal "published", landing_page.landing_page_public_status
    assert_nil @other_business.business_campaigns.find_by(name: "Google Ads")

    get business_url(@business)
    assert_response :success
    assert_select "#external-lp-#{landing_page.id}" do
      assert_select "dt", text: "GitHub"
      assert_select "form[action='#{publish_landing_page_business_access_settings_path(@business, landing_page_id: landing_page.id)}']", count: 0
      assert_select "a", text: "LP詳細"
    end
  end

  test "business can store multiple services and primary service configures execution profile" do
    assert_difference -> { @business.business_services.count }, 2 do
      save_service(name: "API", repository: "https://github.com/example/api", url: "https://api.example.com")
      save_service(name: "Worker", repository: "https://github.com/example/worker", url: "https://worker.example.com")
    end

    services = @business.business_services.order(:created_at)
    assert_equal %w[API Worker], services.pluck(:name)
    assert_equal "rails", services.first.metadata.to_h["framework"]
    assert_equal "main", services.second.metadata.to_h["branch"]
    profile = @business.reload.business_execution_profile
    assert_equal "https://github.com/example/api", profile.github_repository
    assert_equal "https://api.example.com", profile.production_url
    assert_equal "api-web", profile.render_service_name
    assert_nil @other_business.reload.business_execution_profile
  end

  test "landing pages are independent records and sync task targets only the landing page repository" do
    save_service(name: "Service", repository: "https://github.com/example/service", url: "https://service.example.com")

    assert_difference -> { @business.business_prototypes.active.external_landing_pages.count }, 2 do
      save_landing_page(name: "TOP", path: "/ai-reception", repository: "https://github.com/example/lp-top")
      save_landing_page(name: "広告", path: "/lp/ad-001", repository: "https://github.com/example/lp-ad")
    end

    top = @business.business_prototypes.active.external_landing_pages.find_by!(name: "TOP")
    assert_equal BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE, top.metadata.to_h["role"]
    assert_equal "/ai-reception", top.landing_page_ga4_path
    assert_equal "https://lp.example.com/ai-reception", top.metadata.to_h["gsc_url"]
    assert_equal "cloudflare_pages", top.metadata.to_h["hosting_provider"]

    assert_difference [ "ActionCandidate.count", "AutoRevisionTask.count" ], 1 do
      post landing_page_task_business_access_settings_url(@business, landing_page_id: top.id)
    end
    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    task = @business.auto_revision_tasks.order(:created_at).last
    assert_equal "external_lp_sync", task.metadata.to_h["workflow_type"]
    assert_equal "https://github.com/soregaaashiii/aicoo-lp", task.effective_codex_repository_url
    assert_equal "cloudflare_pages", task.effective_deploy_target
    assert task.metadata.to_h["service_repository_protected"]
    assert_not_equal @business.business_execution_profile.github_repository, task.effective_codex_repository_url
    submission = Aicoo::CodexSubmissionBuilder.new(task, force: true).call.submission
    assert_equal "https://github.com/soregaaashiii/aicoo-lp", submission.repository_url
    assert_equal "main", submission.base_branch
    assert_equal "lp-top", submission.project_folder
    assert_not_includes submission.prompt, "api-web"
    assert_includes submission.prompt, "Cloudflare Pages"
    assert_includes submission.prompt, "aicoo-lp"
    assert_includes submission.prompt, "Auto Deploy: 不可"
  end

  test "one shared ga4 and gsc setting supports one hundred landing pages" do
    patch measurement_business_access_settings_url(@business), params: {
      measurement_access: {
        public_url: "https://lp.example.com",
        ga4_measurement_id: "G-TEST123",
        ga4_property_id: "123456789",
        gsc_site_url: "https://lp.example.com",
        activity_api_enabled: "1"
      }
    }
    assert_redirected_to business_url(@business, anchor: "business-access-urls")

    registry = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business)
    assert_difference -> { @business.business_prototypes.active.external_landing_pages.count }, 100 do
      100.times do |index|
        registry.save!(
          name: "LP #{index + 1}",
          source_type: "github",
          repository_url: "https://github.com/example/lp-#{index + 1}",
          branch: "main",
          url: "https://lp.example.com/lp/#{index + 1}",
          ga4_page_path: "/lp/#{index + 1}",
          public_status: "published"
        )
      end
    end

    assert_equal 1, AicooAnalyticsSite.where(business: @business).count
    site = AicooAnalyticsSite.find_by!(business: @business)
    assert_equal "123456789", site.ga4_property_id
    assert_equal "https://lp.example.com", site.gsc_site_url
    assert_equal 1, site.analytics_source_settings.where(source_type: "ga4").count
    assert_equal 1, site.analytics_source_settings.where(source_type: "gsc").count
    assert Aicoo::LpIntegration::Overview.new(@business.reload).activity_api_enabled?
    assert_equal "aicoo-lp", Aicoo::CloudflarePages::Configuration.new(env: {}).project_name
    assert_equal 100, @business.business_prototypes.active.external_landing_pages.distinct.count
    assert_equal 1, @business.business_campaigns.count
  end

  test "campaign and landing page updates stay scoped to their business" do
    own_campaign = @business.business_campaigns.create!(name: "Own", campaign_type: "seo")
    other_campaign = @other_business.business_campaigns.create!(name: "Other", campaign_type: "seo")

    assert_raises ActiveRecord::RecordNotFound do
      Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
        campaign_id: other_campaign.id,
        name: "Wrong",
        source_type: "public_url",
        url: "https://lp.example.com/wrong"
      )
    end
    assert_equal 0, own_campaign.landing_pages.count
    assert_equal 0, other_campaign.landing_pages.count
  end

  test "landing page update and delete stay scoped to the selected business" do
    own = Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
      name: "Own LP", source_type: "public_url", url: "https://lp.example.com/own", ga4_page_path: "/own"
    )
    other = Aicoo::LpIntegration::LandingPageRegistry.new(business: @other_business).save!(
      name: "Other LP", source_type: "public_url", url: "https://other.example.com/lp", ga4_page_path: "/lp"
    )

    patch landing_page_business_access_settings_url(@business), params: {
      lp_access: {
        landing_page_id: other.id,
        name: "改ざん",
        source_type: "public_url",
        url: "https://malicious.example.com",
        ga4_page_path: "/malicious"
      }
    }
    assert_response :not_found
    assert_equal "Other LP", other.reload.name

    delete remove_landing_page_business_access_settings_url(@business, landing_page_id: own.id)
    assert_redirected_to business_url(@business, anchor: "business-access-urls")
    assert_equal "archived", own.reload.status
    assert_equal "active", other.reload.status
  end

  test "service update stays scoped to the selected business" do
    other_service = @other_business.business_services.create!(name: "Other Service")

    patch service_business_access_settings_url(@business), params: {
      service_access: {
        business_service_id: other_service.id,
        name: "改ざん",
        github_repository: "https://github.com/malicious/service",
        branch: "main",
        framework: "rails"
      }
    }

    assert_response :not_found
    assert_equal "Other Service", other_service.reload.name
    assert_equal 0, @business.business_services.count
  end

  private

  def save_service(name:, repository:, url:)
    patch service_business_access_settings_url(@business), params: {
      service_access: {
        name:,
        github_repository: repository,
        branch: "main",
        framework: "rails",
        render_service_name: "#{name.downcase}-web",
        service_url: url,
        health_check_url: "#{url}/up",
        deploy_target: "render",
        activity_api_endpoint: "#{url}/activity",
        auto_deploy_enabled: "0"
      }
    }
    assert_redirected_to business_url(@business, anchor: "business-access-urls")
  end

  def save_campaign(name:, campaign_type:)
    patch campaign_business_access_settings_url(@business), params: {
      campaign_access: { name:, campaign_type:, status: "active" }
    }
    assert_redirected_to business_url(@business, anchor: "business-access-urls")
  end

  def save_landing_page(name:, path:, repository:, campaign: nil)
    Aicoo::LpIntegration::LandingPageRegistry.new(business: @business).save!(
      campaign_id: campaign&.id,
      name:,
      source_type: "lovable_github",
      repository_url: repository,
      branch: "main",
      lovable_project_url: "https://lovable.dev/projects/#{name.parameterize}",
      url: "https://lp.example.com#{path}",
      ga4_page_path: path,
      public_status: "published",
      cta: "無料相談",
      improvement_target: "CTA"
    )
  end
end
