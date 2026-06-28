class PublicSitemapsController < ApplicationController
  def show
    AicooLabLandingPage.publish_due!
    @landing_pages = AicooLabLandingPage.publicly_available.order(published_at: :desc, created_at: :desc)
    xml = sitemap_xml

    response.headers["Content-Length"] = xml.bytesize.to_s
    render plain: xml, content_type: "application/xml", layout: false
  end

  private

  def sitemap_xml
    [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">",
      sitemap_url_node(public_url_for(root_path), sitemap_root_last_modified_at, "daily", "0.8"),
      @landing_pages.map { |landing_page| landing_page_url_node(landing_page) }.join,
      "</urlset>"
    ].join("\n")
  end

  def sitemap_root_last_modified_at
    @landing_pages.maximum(:updated_at) || AicooLabLandingPage.maximum(:updated_at) || Time.current
  end

  def landing_page_url_node(landing_page)
    sitemap_url_node(
      public_url_for(public_lp_path(landing_page.published_slug)),
      landing_page.updated_at,
      "weekly",
      "0.7"
    )
  end

  def sitemap_url_node(location, last_modified_at, changefreq, priority)
    <<~XML
        <url>
          <loc>#{ERB::Util.h(location)}</loc>
          <lastmod>#{ERB::Util.h(last_modified_at.iso8601)}</lastmod>
          <changefreq>#{changefreq}</changefreq>
          <priority>#{priority}</priority>
        </url>
    XML
  end

  def public_url_for(path)
    base_url = ENV["AICOO_PUBLIC_BASE_URL"].presence || request.base_url
    "#{base_url.delete_suffix("/")}#{path.start_with?("/") ? path : "/#{path}"}"
  end
end
