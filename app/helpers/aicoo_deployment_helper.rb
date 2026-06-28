module AicooDeploymentHelper
  LOCAL_HOSTS = %w[127.0.0.1 localhost ::1].freeze

  def aicoo_public_base_url
    ENV["AICOO_PUBLIC_BASE_URL"].presence || ENV["RENDER_EXTERNAL_URL"].presence
  end

  def aicoo_current_base_url_external_shareable?
    LOCAL_HOSTS.exclude?(request.host)
  end

  def aicoo_current_base_url_label
    if aicoo_current_base_url_external_shareable?
      request.base_url
    else
      "#{request.base_url}（外部共有不可）"
    end
  end

  def aicoo_public_lp_url_for(landing_page)
    return nil if landing_page.blank? || landing_page.published_slug.blank?

    base_url = aicoo_public_base_url
    return public_lp_url(landing_page.published_slug) if base_url.blank?

    "#{base_url.delete_suffix('/')}/lp/#{landing_page.published_slug}"
  end
end
