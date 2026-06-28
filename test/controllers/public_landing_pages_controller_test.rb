require "test_helper"

class PublicLandingPagesControllerTest < ActionDispatch::IntegrationTest
  test "public landing page index lists only published landing pages" do
    published = create_landing_page(headline: "公開LPタイトル", published_slug: "published-lp")
    create_landing_page(headline: "非公開LPタイトル", status: "preview_ready", public_status: "draft", published_slug: nil)

    get public_landing_pages_url

    assert_response :success
    assert_includes response.body, "公開中のランディングページ"
    assert_includes response.body, published.headline
    assert_includes response.body, public_lp_path(published.published_slug)
    assert_not_includes response.body, "非公開LPタイトル"
    assert_not_includes response.body, "owner"
    assert_not_includes response.body, "admin"
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

    get sitemap_url(format: :xml)

    assert_response :success
    assert_includes response.media_type, "xml"
    assert_includes response.body, public_landing_pages_path
    assert_includes response.body, public_lp_path(landing_page.published_slug)
    assert_includes response.body, "<lastmod>"
    assert_not_includes response.body, "draft-sitemap-lp"
    assert_not_includes response.body, dashboard_url
    assert_not_includes response.body, "/admin"
    assert_not_includes response.body, "/owner"
  end

  test "robots allows public landing pages and blocks management paths" do
    get robots_url

    assert_response :success
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
end
