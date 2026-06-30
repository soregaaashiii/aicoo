require "test_helper"

class AicooActivityLogRetryJobTest < ActiveJob::TestCase
  test "marks queued item as sent when retry succeeds" do
    queue_item = AicooActivityLogQueue.create!(
      payload: {
        business_key: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id: "1",
        title: "Shop作成"
      },
      next_retry_at: 1.minute.ago
    )

    with_singleton_stub(AicooActivityLogger, :deliver_payload, ->(payload) { { ok: true } }) do
      AicooActivityLogRetryJob.perform_now
    end

    assert_equal "sent", queue_item.reload.status
  end

  private

  def with_singleton_stub(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
