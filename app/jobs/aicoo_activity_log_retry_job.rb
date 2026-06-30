class AicooActivityLogRetryJob < ApplicationJob
  queue_as :default

  def perform(limit: 50)
    AicooActivityLogQueue.retryable.limit(limit).find_each do |queue_item|
      retry_item(queue_item)
    end
  end

  private

  def retry_item(queue_item)
    result = AicooActivityLogger.deliver_payload(queue_item.payload)
    if result[:ok]
      queue_item.mark_sent!
    else
      queue_item.schedule_retry!(result[:error].presence || "Activity log retry failed")
    end
  rescue StandardError => e
    queue_item.schedule_retry!("#{e.class}: #{e.message}")
  end
end
