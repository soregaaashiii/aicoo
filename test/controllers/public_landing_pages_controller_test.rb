require "test_helper"
require "rexml/document"

class PublicLandingPagesControllerTest < ActionDispatch::IntegrationTest
  test "public landing page index lists only published landing pages" do
    published = create_landing_page(headline: "公開LPタイトル", published_slug: "published-lp")
    create_landing_page(headline: "非公開LPタイトル", status: "preview_ready", public_status: "draft", published_slug: nil)
    create_landing_page(headline: "予約中LPタイトル", status: "preview_ready", public_status: "scheduled", published_slug: "scheduled-list-lp", scheduled_publish_at: 1.day.from_now)
    create_landing_page(headline: "アーカイブLPタイトル", status: "unpublished", public_status: "archived", published_slug: "archived-list-lp")

    get public_landing_pages_url

    assert_response :success
    assert_includes response.body, "公開中のランディングページ"
    assert_includes response.body, published.headline
    assert_includes response.body, public_lp_path(published.published_slug)
    assert_not_includes response.body, "非公開LPタイトル"
    assert_not_includes response.body, "予約中LPタイトル"
    assert_not_includes response.body, "アーカイブLPタイトル"
    assert_no_aicoo_management_links
  end

  test "root path shows public landing page top without management links" do
    published = create_landing_page(headline: "Root公開LPタイトル", published_slug: "root-published-lp")
    create_landing_page(headline: "Root下書きLPタイトル", status: "preview_ready", public_status: "draft", published_slug: "root-draft-lp")

    with_basic_auth_env do
      get root_url
    end

    assert_response :success
    assert_includes response.body, "公開中のランディングページ"
    assert_includes response.body, published.headline
    assert_includes response.body, public_lp_path(published.published_slug)
    assert_not_includes response.body, "Root下書きLPタイトル"
    assert_includes response.body, "index,follow"
    assert_includes response.body, "rel=\"canonical\""
    assert_no_aicoo_management_links
  end

  test "public layout renders ga4 tag and explicit page view in production" do
    create_landing_page(headline: "GA4公開LPタイトル", published_slug: "ga4-public-lp")

    with_env_values("GA4_MEASUREMENT_ID" => "G-E5KCHJTFVP") do
      with_rails_env("production") do
        get root_url
      end
    end

    assert_response :success
    assert_includes response.body, "https://www.googletagmanager.com/gtag/js?id=G-E5KCHJTFVP"
    assert_includes response.body, "gtag('config', 'G-E5KCHJTFVP', { send_page_view: false });"
    assert_includes response.body, "gtag('event', 'page_view'"
  end

  test "public lp alias shows the same published landing page list" do
    published = create_landing_page(headline: "Alias LPタイトル", published_slug: "alias-published-lp")
    create_landing_page(headline: "Alias Draft LP", status: "preview_ready", public_status: "draft", published_slug: "alias-draft-lp")

    get public_lp_index_url

    assert_response :success
    assert_includes response.body, published.headline
    assert_includes response.body, public_lp_path(published.published_slug)
    assert_not_includes response.body, "Alias Draft LP"
    assert_no_aicoo_management_links
  end

  test "public landing page is accessible without basic auth and records view" do
    landing_page = create_landing_page(
      headline: "一般公開LP",
      published_slug: "open-lp",
      seo_title: "SEO用タイトル",
      seo_description: "SEO用説明文です。",
      og_title: "OG用タイトル",
      og_description: "OG用説明文です。",
      og_image_url: "https://example.com/og.png"
    )

    with_basic_auth_env do
      assert_difference("AicooLabLandingPageEvent.where(event_type: 'view').count", 1) do
        get public_lp_url(landing_page.published_slug)
      end
    end

    assert_response :success
    assert_includes response.body, "一般公開LP"
    assert_includes response.body, "SEO用タイトル"
    assert_includes response.body, "SEO用説明文です。"
    assert_includes response.body, "rel=\"canonical\""
    assert_includes response.body, "property=\"og:title\" content=\"OG用タイトル\""
    assert_includes response.body, "name=\"twitter:card\" content=\"summary_large_image\""
    assert_includes response.body, "index,follow"
    assert_not_includes response.body, "CEO MODE"
    assert_not_includes response.body, "SYSTEM MODE"
    assert_no_aicoo_management_links
  end

  test "scheduled landing page is published automatically when due" do
    landing_page = create_landing_page(
      headline: "予約公開LP",
      published_slug: "scheduled-lp",
      status: "preview_ready",
      public_status: "scheduled",
      scheduled_publish_at: 1.minute.ago
    )

    get public_lp_url(landing_page.published_slug)

    assert_response :success
    assert_equal "published", landing_page.reload.public_status
    assert_includes response.body, "予約公開LP"
  end

  test "future scheduled landing page is not public yet" do
    landing_page = create_landing_page(
      headline: "未来予約LP",
      published_slug: "future-lp",
      status: "preview_ready",
      public_status: "scheduled",
      scheduled_publish_at: 1.day.from_now
    )

    get public_lp_url(landing_page.published_slug)

    assert_response :not_found
  end

  test "paused landing page shows pause page without canonical and is noindex" do
    landing_page = create_landing_page(headline: "Paused LP", published_slug: "paused-lp")
    landing_page.pause!(reason: "manual", operator: "admin", comment: "確認中")

    assert_no_difference("AicooLabLandingPageEvent.where(event_type: 'view').count") do
      get public_lp_url(landing_page.published_slug)
    end

    assert_response :success
    assert_includes response.body, "現在公開停止中です"
    assert_includes response.body, "noindex,nofollow"
    assert_not_includes response.body, "rel=\"canonical\""
    assert_no_aicoo_management_links
  end

  test "old landing page slug redirects permanently to current slug" do
    landing_page = create_landing_page(headline: "Slug LP", published_slug: "old-slug")
    landing_page.update!(published_slug: "new-slug")

    get public_lp_url("old-slug")

    assert_response :moved_permanently
    assert_redirected_to public_lp_path("new-slug")
  end

  test "public landing page cta and signup use public paths" do
    landing_page = create_landing_page(headline: "Signup LP", published_slug: "signup-lp")

    assert_difference("AicooLabLandingPageEvent.where(event_type: 'cta_click').count", 1) do
      post public_lp_cta_click_url(landing_page.published_slug)
    end
    assert_redirected_to public_lp_signup_path(landing_page.published_slug)

    get public_lp_signup_url(landing_page.published_slug)
    assert_response :success

    assert_difference("AicooLabSignup.count", 1) do
      post public_lp_signup_url(landing_page.published_slug), params: {
        aicoo_lab_signup: { email: "public@example.com", note: "公開LPから登録" }
      }
    end
    assert_response :success
  end

  test "public landing page records scroll event" do
    landing_page = create_landing_page(headline: "Scroll LP", published_slug: "scroll-lp")

    assert_difference("AicooLabLandingPageEvent.where(event_type: 'scroll').count", 1) do
      post public_lp_scroll_url(landing_page.published_slug), params: { depth: 75 }, as: :json
    end

    assert_response :no_content
    assert_equal 75, AicooLabLandingPageEvent.where(event_type: "scroll").last.metadata["depth"]
  end

  test "sitemap includes public landing pages and excludes management urls" do
    landing_page = create_landing_page(headline: "Sitemap LP", published_slug: "sitemap-lp")
    create_landing_page(headline: "Draft Sitemap LP", public_status: "draft", published_slug: "draft-sitemap-lp")
    create_landing_page(headline: "Scheduled Sitemap LP", status: "preview_ready", public_status: "scheduled", published_slug: "scheduled-sitemap-lp", scheduled_publish_at: 1.day.from_now)
    create_landing_page(headline: "Archived Sitemap LP", status: "unpublished", public_status: "archived", published_slug: "archived-sitemap-lp")
    paused = create_landing_page(headline: "Paused Sitemap LP", published_slug: "paused-sitemap-lp")
    paused.pause!(reason: "manual", operator: "admin")

    get sitemap_url(format: :xml)

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert response.body.start_with?("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    assert_not_equal [ 0xEF, 0xBB, 0xBF ], response.body.bytes.first(3)
    assert_equal 0, response.body.index("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    document = REXML::Document.new(response.body)
    assert_equal "urlset", document.root.name
    assert_equal "http://www.sitemaps.org/schemas/sitemap/0.9", document.root.namespace
    assert_includes response.body, "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"
    assert_includes response.body, "<url>"
    assert_includes response.body, "<loc>"
    assert_includes response.body, root_path
    assert_includes response.body, public_lp_path(landing_page.published_slug)
    assert_includes response.body, "<lastmod>"
    assert_not_includes response.body, "<!DOCTYPE html>"
    assert_not_includes response.body, "<html"
    assert_not_includes response.body, "draft-sitemap-lp"
    assert_not_includes response.body, "scheduled-sitemap-lp"
    assert_not_includes response.body, "archived-sitemap-lp"
    assert_not_includes response.body, "paused-sitemap-lp"
    assert_not_includes response.body, dashboard_url
    assert_not_includes response.body, "/admin"
    assert_not_includes response.body, "/owner"
  end

  test "robots allows public landing pages and blocks management paths" do
    get robots_url

    assert_response :success
    assert_includes response.body, "Allow: /"
    assert_includes response.body, "Allow: /sitemap.xml"
    assert_includes response.body, "Allow: /lp"
    assert_includes response.body, "Disallow: /admin"
    assert_includes response.body, "Disallow: /owner"
    assert_includes response.body, sitemap_path(format: :xml)
  end

  private

  def create_landing_page(headline:, published_slug:, status: "published", public_status: nil, **attributes)
    experiment = AicooLabExperiment.create!(
      title: headline,
      experiment_type: "lp",
      acquisition_channel: "sns",
      approval_status: "approved"
    )
    experiment.create_aicoo_lab_landing_page!(
      headline:,
      subheadline: "#{headline}の説明",
      body: "#{headline}の本文",
      cta_text: "事前登録する",
      status:,
      public_status: public_status || (status == "published" ? "published" : "draft"),
      published_slug:,
      published_at: (Time.current if status == "published"),
      **attributes
    )
  end

  def with_basic_auth_env(&)
    with_env(
      "AICOO_ENABLE_BASIC_AUTH" => "true",
      "AICOO_BASIC_AUTH_USERNAME" => "aicoo-admin",
      "AICOO_BASIC_AUTH_PASSWORD" => "secret-password",
      &
    )
  end

  def with_env(values)
    originals = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    originals.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def with_env_values(values, &)
    originals = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_rails_env(name)
    original = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new(name) }
    yield
  ensure
    Rails.define_singleton_method(:env) { original.call }
  end

  def assert_no_aicoo_management_links
    assert_no_match(/\b(?:href|action)=["']\/(?:owner|admin|settings|system|aicoo)(?:\/|["'?])/, response.body)
  end
end
