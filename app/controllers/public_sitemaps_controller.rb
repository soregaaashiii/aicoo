class PublicSitemapsController < ApplicationController
  def show
    AicooLabLandingPage.publish_due!
    @landing_pages = AicooLabLandingPage.publicly_available.order(published_at: :desc, created_at: :desc)

    render plain: sitemap_xml, content_type: "application/xml", layout: false
  end

  private

  def sitemap_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{sitemap_url_node(public_url_for(root_path), Time.current, "daily", "0.8")}
      #{@landing_pages.map { |landing_page| landing_page_url_node(landing_page) }.join}
      </urlset>
    XML
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
