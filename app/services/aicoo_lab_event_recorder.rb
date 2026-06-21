require "digest"

class AicooLabEventRecorder
  def initialize(landing_page, request)
    @landing_page = landing_page
    @request = request
  end

  def record!(event_type, metadata: {})
    landing_page.aicoo_lab_landing_page_events.create!(
      event_type:,
      ip_hash:,
      user_agent: request.user_agent,
      referrer: request.referrer,
      metadata:
    )
  end

  def self.ip_hash_for(ip)
    Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}:#{ip}")
  end

  private

  attr_reader :landing_page, :request

  def ip_hash
    self.class.ip_hash_for(request.remote_ip)
  end
end
