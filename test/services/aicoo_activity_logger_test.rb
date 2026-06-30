require "test_helper"

class AicooActivityLoggerTest < ActiveSupport::TestCase
  test "queues payload when api url is missing" do
    previous_url = ENV["AICOO_API_URL"]
    previous_key = ENV["AICOO_API_KEY"]
    ENV.delete("AICOO_API_URL")
    ENV["AICOO_API_KEY"] = "key"

    assert_difference -> { AicooActivityLogQueue.count }, 1 do
      result = AicooActivityLogger.log(
        business_key: "suelog",
        activity_type: "shop_created",
        resource_type: "Shop",
        resource_id: "1",
        title: "Shop作成",
        idempotency_key: "logger-test"
      )
      assert_equal false, result[:ok]
      assert_equal true, result[:queued]
    end
  ensure
    ENV["AICOO_API_URL"] = previous_url
    ENV["AICOO_API_KEY"] = previous_key
  end
end
