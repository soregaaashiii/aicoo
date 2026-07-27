require "json"

module Webhooks
  class GithubController < ActionController::API
    def create
      body = request.raw_post
      unless configuration.configured?
        configuration.record!(
          status: "webhook_secret_missing",
          failure: true,
          attributes: request_attributes.merge("error" => "webhook_secret_missing")
        )
        return render json: { ok: false, error: "webhook_secret_missing" }, status: :service_unavailable
      end
      unless Aicoo::Lovable::GithubWebhookSignature.valid?(
        payload: body,
        signature: request.headers["X-Hub-Signature-256"],
        secret: configuration.secret
      )
        configuration.record!(
          status: "signature_mismatch",
          failure: true,
          attributes: request_attributes.merge("error" => "signature_mismatch")
        )
        return render json: { ok: false, error: "signature_mismatch" }, status: :unauthorized
      end

      result = Aicoo::Lovable::GithubPushReceiver.new(configuration:).call(
        event: request.headers["X-GitHub-Event"],
        delivery_id: request.headers["X-GitHub-Delivery"],
        payload: JSON.parse(body)
      )
      render json: {
        ok: true,
        status: result.status,
        generation_run_id: result.generation_run_id,
        landing_page_id: result.landing_page_id,
        duplicate: result.duplicate,
        reason: result.reason
      }.compact, status: result.status == "accepted" ? :accepted : :ok
    rescue JSON::ParserError
      configuration.record!(
        status: "invalid_json",
        failure: true,
        attributes: request_attributes.merge("error" => "invalid_json")
      )
      render json: { ok: false, error: "invalid_json" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[Lovable GitHub Webhook] #{e.class}: #{e.message}")
      render json: { ok: false, error: "webhook_processing_failed" }, status: :internal_server_error
    end

    private

    def configuration
      @configuration ||= Aicoo::Lovable::GithubWebhookConfiguration.new
    end

    def request_attributes
      {
        "event" => request.headers["X-GitHub-Event"].to_s,
        "delivery_id" => request.headers["X-GitHub-Delivery"].to_s
      }
    end
  end
end
