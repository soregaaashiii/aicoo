require "digest"

class PublicBusinessServicesController < ApplicationController
  layout "public_lp"

  before_action :set_business_service

  def show
    record_activity!("mvp_view", title: "MVP画面を表示")
  end

  def create_signup
    email = params.dig(:service_signup, :email).to_s.strip
    note = params.dig(:service_signup, :note).to_s.strip

    if email.blank?
      flash.now[:alert] = "メールアドレスを入力してください。"
      render :show, status: :unprocessable_content
      return
    end

    record_activity!(
      "mvp_signup",
      title: "MVP事前登録",
      metadata: {
        "email" => email,
        "note" => note,
        "signup_source" => "public_business_service",
        "user_agent" => request.user_agent,
        "referrer" => request.referrer
      }
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

  def record_activity!(activity_type, title:, metadata: {})
    @business.business_activity_logs.create!(
      source_app: "aicoo",
      source_method: "public_business_service",
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
        "service_url" => @business_service.url
      }.merge(metadata)
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
end
