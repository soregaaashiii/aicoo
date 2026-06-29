module ApplicationHelper
  def ga4_measurement_id
    ENV["GA4_MEASUREMENT_ID"].presence
  end

  def render_ga4_tag?
    Rails.env.production? && ga4_measurement_id.present?
  end

  def google_site_verification
    ENV["GOOGLE_SITE_VERIFICATION"].presence
  end

  def render_google_site_verification?
    Rails.env.production? && google_site_verification.present?
  end

  def public_site_base_url
    ENV["AICOO_PUBLIC_BASE_URL"].presence&.delete_suffix("/")
  end

  def public_absolute_url(path)
    base_url = public_site_base_url.presence || (request.base_url if respond_to?(:request) && request)
    return path if base_url.blank?

    "#{base_url.delete_suffix("/")}#{path.start_with?("/") ? path : "/#{path}"}"
  end

  def stage_label(stage)
    {
      "idea" => "Idea",
      "discovery" => "Discovery",
      "score" => "Score",
      "serp" => "SERP",
      "lp" => "LP",
      "publish" => "公開",
      "measure" => "Measure",
      "improve" => "Improve",
      "deploy" => "Deploy",
      "learning" => "Learning",
      "mvp" => "MVP",
      "decision" => "Continue / Pivot / End"
    }.fetch(stage.to_s, stage.to_s)
  end
end
