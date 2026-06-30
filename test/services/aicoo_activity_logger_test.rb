require "test_helper"

class AicooActivityLoggerTest < ActiveSupport::TestCase
  test "queues payload when api url is missing" do
    previous_url = ENV["AICOO_API_URL"]
    previous_key = ENV["AICOO_API_KEY"]
    previous_token = ENV["AICOO_ACTIVITY_API_TOKEN"]
    ENV.delete("AICOO_API_URL")
    ENV["AICOO_API_KEY"] = "key"
    ENV.delete("AICOO_ACTIVITY_API_TOKEN")

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
    ENV["AICOO_ACTIVITY_API_TOKEN"] = previous_token
  end

  test "builds suelog activity api payload aliases" do
    payload = AicooActivityLogger.new.send(
      :build_payload,
      business_key: "suelog",
      activity_type: "data_added",
      source_type: "shop",
      source_id: 12,
      title: "店舗を追加",
      summary: "梅田の店舗を追加",
      metadata: { area: "梅田" }
    )

    assert_equal "suelog", payload[:business_key]
    assert_equal "shop", payload[:source_type]
    assert_equal 12, payload[:source_id]
    assert_equal "Shop", payload[:resource_type]
    assert_equal 12, payload[:resource_id]
    assert_equal "梅田の店舗を追加", payload[:summary]
  end

  test "uses activity api token before legacy api key" do
    previous_token = ENV["AICOO_ACTIVITY_API_TOKEN"]
    previous_key = ENV["AICOO_API_KEY"]
    ENV["AICOO_ACTIVITY_API_TOKEN"] = "activity-token"
    ENV["AICOO_API_KEY"] = "legacy-key"

    assert_equal "activity-token", AicooActivityLogger.new.send(:api_key)
  ensure
    ENV["AICOO_ACTIVITY_API_TOKEN"] = previous_token
    ENV["AICOO_API_KEY"] = previous_key
  end
end
