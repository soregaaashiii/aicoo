require "net/http"
require "uri"

class AicooActivityLogger
  class << self
    def log(**attributes)
      new.log(**attributes)
    end

    def deliver_payload(payload)
      new.deliver_payload(payload)
    end
  end

  def log(**attributes)
    return disabled_result if disabled?

    payload = build_payload(attributes)
    response = post_payload(payload)
    return { ok: true, queued: false, status: response.code.to_i } if response.is_a?(Net::HTTPSuccess)

    queue_payload!(payload, "HTTP #{response.code}: #{response.body}")
  rescue StandardError => e
    queue_payload!(payload || build_payload(attributes), "#{e.class}: #{e.message}")
  end

  def deliver_payload(payload)
    response = post_payload(payload)
    return { ok: true, status: response.code.to_i } if response.is_a?(Net::HTTPSuccess)

    { ok: false, error: "HTTP #{response.code}: #{response.body}" }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  private

  def disabled?
    ENV["AICOO_ACTIVITY_LOGGING_ENABLED"].to_s == "false"
  end

  def disabled_result
    { ok: true, skipped: true, reason: "disabled" }
  end

  def build_payload(attributes)
    attrs = attributes.symbolize_keys
    resource_type = attrs[:resource_type].presence || attrs[:source_type].to_s.camelize.presence
    resource_id = attrs[:resource_id].presence || attrs[:source_id]
    source_type = attrs[:source_type].presence || resource_type.to_s.underscore
    {
      business_id: attrs[:business_id],
      business_key: attrs[:business_key] || ENV["AICOO_BUSINESS_KEY"],
      source_app: attrs[:source_app] || ENV["AICOO_SOURCE_APP"] || Rails.application.class.module_parent_name.underscore,
      activity_type: attrs[:activity_type],
      source_type:,
      source_id: resource_id,
      resource_type:,
      resource_id:,
      title: attrs[:title],
      summary: attrs[:summary] || attrs[:diff_summary],
      occurred_at: attrs[:occurred_at] || Time.current.iso8601,
      changed_fields: attrs[:changed_fields] || {},
      before_snapshot: attrs[:before_snapshot] || {},
      after_snapshot: attrs[:after_snapshot] || {},
      diff_summary: attrs[:diff_summary],
      metadata: attrs[:metadata] || {},
      estimated_work_seconds: attrs[:estimated_work_seconds],
      source_method: "logger",
      idempotency_key: attrs[:idempotency_key]
    }.compact
  end

  def post_payload(payload)
    uri = URI.join(api_url, "/api/aicoo/activity_logs")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{api_key}"
    request.body = payload.to_json
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
  end

  def api_url
    ENV.fetch("AICOO_API_URL")
  end

  def api_key
    ENV["AICOO_ACTIVITY_API_TOKEN"].presence ||
      ENV["AICOO_ACTIVITY_API_KEY"].presence ||
      ENV.fetch("AICOO_API_KEY")
  end

  def queue_payload!(payload, error_message)
    AicooActivityLogQueue.create!(
      payload:,
      idempotency_key: payload[:idempotency_key] || payload["idempotency_key"],
      error_message:,
      next_retry_at: Time.current + 5.minutes
    )
    { ok: false, queued: true, error: error_message }
  end
end
