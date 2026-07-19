require "digest"

class PublicBusinessServicesController < ApplicationController
  layout "public_lp"

  before_action :set_business_service
  before_action :set_service_context

  def show
    record_activity!("mvp_view", title: "MVP画面を表示")
  end

  def create_signup
    request_attributes = service_request_attributes
    email = request_attributes["email"].to_s.strip

    if email.blank?
      flash.now[:alert] = "メールアドレスを入力してください。"
      render :show, status: :unprocessable_content
      return
    end

    record_activity!(
      "mvp_signup",
      title: "MVP利用リクエスト",
      metadata: request_attributes.merge(
        "request_status" => "received",
        "signup_source" => "public_business_service",
        "user_agent" => request.user_agent,
        "referrer" => request.referrer
      )
    )
    @signup_completed = true
    render :show
  end

  private

  def set_business_service
    @business_service = BusinessService
      .includes(:business)
      .where(status: %w[building live production])
      .find(params.expect(:id))
    raise ActiveRecord::RecordNotFound if @business_service.business.deleted?

    @business = @business_service.business
  end

  def set_service_context
    @service_title = @business_service.name.to_s.sub(/\s*SaaS\z/, "").presence || @business.name
    @service_summary = service_summary
    @recent_request_count = @business.business_activity_logs
      .where(activity_type: "mvp_signup", resource_type: "BusinessService", resource_id: @business_service.id.to_s)
      .count
    @latest_request_at = @business.business_activity_logs
      .where(activity_type: "mvp_signup", resource_type: "BusinessService", resource_id: @business_service.id.to_s)
      .maximum(:occurred_at)
  end

  def service_request_attributes
    raw = params.fetch(:service_signup, {}).permit(
      :email,
      :company_name,
      :website_url,
      :request_type,
      :current_channel,
      :monthly_goal,
      :note
    )
    raw.to_h.transform_values { |value| value.to_s.strip }
  end

  def record_activity!(activity_type, title:, metadata: {})
    BusinessActivityLog.record!(
      business: @business,
      attributes: {
        source_app: "aicoo",
        source_method: "logger",
        activity_type:,
        resource_type: "BusinessService",
        resource_id: @business_service.id.to_s,
        title:,
        occurred_at: Time.current,
        detected_at: Time.current,
        diff_summary: "#{@business_service.name}: #{title}",
        idempotency_key: idempotency_key_for(activity_type, metadata),
        metadata: {
          "business_service_id" => @business_service.id,
          "service_name" => @business_service.name,
          "service_url" => @business_service.url,
          "activity_source" => "public_business_service"
        }.merge(metadata)
      }
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  def idempotency_key_for(activity_type, metadata)
    digest = Digest::SHA256.hexdigest(
      [
        activity_type,
        @business_service.id,
        metadata["email"].to_s.downcase.presence || request.remote_ip,
        Time.current.to_date
      ].join(":")
    )
    "public_business_service:#{digest}"
  end

  def service_summary
    metadata = @business.metadata.to_h
    problem = metadata["problem"].presence || extract_description_label("解決課題")
    customer = metadata["target_customer"].presence || extract_description_label("想定顧客")
    solution = metadata["solution"].presence || @business.name
    [ customer, problem, solution ].compact_blank.join(" / ").presence || "依頼内容を登録し、運営側が初期対応するMVPです。"
  end

  def extract_description_label(label)
    line = @business.description.to_s.lines.find { |text| text.start_with?("#{label}:") }
    line.to_s.sub("#{label}:", "").strip.presence
  end
end
