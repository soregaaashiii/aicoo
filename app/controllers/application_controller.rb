require "digest"

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :reuse_read_only_query_results
  before_action :protect_aicoo_management_area
  before_action :set_robots_header
  before_action :load_daily_run_execution_status
  before_action :load_long_running_operation_monitor

  helper_method :aicoo_settings_navigation_request?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def reuse_read_only_query_results
    if request.get? && request.format.html?
      Aicoo::RequestQueryContext.within { yield }
    else
      yield
    end
  end

  def protect_aicoo_management_area
    return unless aicoo_management_protection_enabled?
    return if public_render_path?

    username = ENV["AICOO_BASIC_AUTH_USERNAME"].to_s
    password = ENV["AICOO_BASIC_AUTH_PASSWORD"].to_s

    if username.blank? || password.blank?
      render plain: "AICOO management access is not configured.", status: :forbidden
      return
    end

    authenticate_or_request_with_http_basic("AICOO") do |provided_username, provided_password|
      secure_basic_auth_match?(provided_username, username) &&
        secure_basic_auth_match?(provided_password, password)
    end
  end

  def aicoo_management_protection_enabled?
    Rails.env.production? || ENV["AICOO_ENABLE_BASIC_AUTH"] == "true"
  end

  def public_render_path?
    request.path == "/" ||
      request.path == "/lp" ||
      request.path.start_with?("/lp/", "/aicoo_lab/lp/", "/assets/") ||
      request.path.in?([ "/robots.txt", "/sitemap.xml" ]) ||
      request.path == "/up" ||
      request.path == "/favicon.ico"
  end

  def set_robots_header
    response.set_header("X-Robots-Tag", "noindex, nofollow") unless public_render_path?
  end

  def load_long_running_operation_monitor
    return if public_render_path?
    return if owner_focus_path?
    return if execution_runs_path?
    return if operation_status_panel_hidden_for_request?
    return unless request.format.html?

    @long_running_operation_monitor = Aicoo::LongRunningOperationMonitor.new(
      running_only: true,
      include_daily_runs: false
    ).call
  rescue StandardError => e
    Rails.logger.warn("Long running operation monitor unavailable: #{e.class}: #{e.message}")
    @long_running_operation_monitor = nil
  end

  def load_daily_run_execution_status
    return if public_render_path?
    return unless request.format.html?

    @daily_run_execution_status = Aicoo::DailyRunExecutionStatus.call(
      include_latest: daily_run_history_status_required?
    )
  rescue StandardError => e
    Rails.logger.warn("Daily run execution status unavailable: #{e.class}: #{e.message}")
    @daily_run_execution_status = nil
  end

  def daily_run_history_status_required?
    (controller_path == "aicoo_daily_runs" && action_name == "index") ||
      (controller_path == "dashboard" && action_name == "show")
  end

  def aicoo_settings_navigation_request?
    controller_path.in?([
      "aicoo_settings",
      "admin/aicoo_auto_revision_settings",
      "admin/aicoo_daily_run_settings",
      "admin/cloudflare_connections",
      "admin/analytics_connections",
      "admin/analytics_imports",
      "admin/analytics_sites",
      "admin/analytics_sources",
      "admin/google_api_imports",
      "admin/google_credentials",
      "admin/lovable",
      "admin/aicoo_lab/lp_learning"
    ])
  end

  def owner_focus_path?
    request.path == "/owner/focus"
  end

  def execution_runs_path?
    request.path.start_with?("/admin/execution_runs")
  end

  def operation_status_panel_hidden_for_request?
    controller_path == "aicoo_daily_runs" && action_name == "show"
  end

  def memory_diagnostics_context(extra = {})
    {
      controller: controller_path,
      action: action_name,
      path: request.path,
      request_id: request.request_id,
      params: safe_memory_diagnostics_params
    }.merge(extra).compact
  end

  def safe_memory_diagnostics_params
    params.to_unsafe_h.slice(
      "id",
      "business_id",
      "mode",
      "filter",
      "tab",
      "page",
      "today_actions_page",
      "home_actions_page"
    )
  end

  def secure_basic_auth_match?(provided_value, expected_value)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(provided_value.to_s),
      Digest::SHA256.hexdigest(expected_value.to_s)
    )
  end
end
