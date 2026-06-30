require "test_helper"

module Admin
  class AicooDailyRunHealthControllerTest < ActionDispatch::IntegrationTest
    test "shows daily run health in manual mode" do
      with_env("AICOO_DAILY_RUN_ENABLED", nil) do
        get admin_aicoo_daily_run_health_url
      end

      assert_response :success
      assert_includes response.body, "Daily Runヘルス"
      assert_includes response.body, "Daily Run Mode"
      assert_includes response.body, "Manual"
      assert_includes response.body, "AICOO_DAILY_RUN_ENABLED"
    end

    test "shows cron ready when env is enabled" do
      with_env("AICOO_DAILY_RUN_ENABLED", "true") do
        get admin_aicoo_daily_run_health_url
      end

      assert_response :success
      assert_includes response.body, "Cron Ready"
      assert_includes response.body, "CronからDaily Runを安全に起動できます"
    end

    private

    def with_env(key, value)
      previous = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
      yield
    ensure
      previous.nil? ? ENV.delete(key) : ENV[key] = previous
    end
  end
end
