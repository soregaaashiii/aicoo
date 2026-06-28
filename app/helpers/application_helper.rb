module ApplicationHelper
  def ga4_measurement_id
    ENV["GA4_MEASUREMENT_ID"].presence
  end

  def render_ga4_tag?
    Rails.env.production? && ga4_measurement_id.present?
  end
end
