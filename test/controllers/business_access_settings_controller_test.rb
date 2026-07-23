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

  test "business detail shows service campaign and shared measurement cards" do
    get business_url(@business)

    assert_response :success
    assert_select "#business-access-urls"
    assert_select "#business-service-access-card", text: /Service/
    assert_select "#business-campaign-access-card", text: /Campaign/
    assert_select "#business-measurement-access-card", text: /計測/
    assert_select "summary", text: "+ Service追加"
    assert_select "summary", text: "+ Campaign追加"
    assert_select "summary", text: "共通計測を設定"
    assert_select "#business-campaign-access-card input[name='measurement_access[ga4_property_id]']", count: 0
    assert_select "#business-campaign-access-card input[name='measurement_access[gsc_site_url]']", count: 0
  end

  test "landing page creation asks only for purpose and hides optional controls in details" do
    campaign = @business.business_campaigns.create!(name: "SEO", campaign_type: "seo", status: "active")

    get business_url(@business)

    assert_response :success
    assert_select "form.lp-creation-form" do
      assert_select "input[name='lp_plan[name]']"
      assert_select "select[name='lp_plan[purpose]']"
      assert_select "textarea[name='lp_plan[notes]']"
      assert_select "details.lp-advanced-settings", text: /詳細設定/
      assert_select "input[name='lp_plan[keywords]']", count: 0
      assert_select "input[name='lp_plan[advanced][keywords]']", count: 1
      assert_select "input[name='lp_plan[campaign_id]'][value='#{campaign.id}']"
      assert_select "input[type='submit'][value='生成開始']"
    end
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
    assert_equal "https://github.com/example/lp-top", task.effective_codex_repository_url
    assert_equal "cloudflare_pages", task.effective_deploy_target
    assert task.metadata.to_h["service_repository_protected"]
    assert_not_equal @business.business_execution_profile.github_repository, task.effective_codex_repository_url
    submission = Aicoo::CodexSubmissionBuilder.new(task, force: true).call.submission
    assert_equal "https://github.com/example/lp-top", submission.repository_url
    assert_equal "main", submission.base_branch
    assert_equal "lp-top", submission.project_folder
    assert_not_includes submission.prompt, "api-web"
    assert_includes submission.prompt, "Cloudflare Pages"
    assert_includes submission.prompt, "Auto Deploy: 不可"
  end

  test "one shared ga4 and gsc setting supports one hundred landing pages" do
    patch measurement_business_access_settings_url(@business), params: {
      measurement_access: {
        public_url: "https://lp.example.com",
        ga4_measurement_id: "G-TEST123",
        ga4_property_id: "123456789",
        gsc_site_url: "https://lp.example.com",
        cloudflare_project_name: "all-business-lps",
        cloudflare_production_url: "https://lp.example.com",
        cloudflare_branch: "main",
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
    assert_equal "all-business-lps", @business.reload.metadata.to_h["lp_cloudflare_project_name"]
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
    patch landing_page_business_access_settings_url(@business), params: {
      lp_access: {
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
      }
    }
    assert_redirected_to business_url(@business, anchor: "business-access-urls")
  end
end
