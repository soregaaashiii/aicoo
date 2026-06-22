require "test_helper"

module Admin
  class AicooDailyRunSettingsControllerTest < ActionDispatch::IntegrationTest
    test "shows daily run settings" do
      get admin_aicoo_daily_run_settings_url

      assert_response :success
      assert_includes response.body, "Daily Run設定"
      assert_includes response.body, "自動実行"
      assert_includes response.body, "成功まで再試行"
      assert_includes response.body, "bin/rails aicoo:daily_run"
    end

    test "updates daily run settings" do
      patch admin_aicoo_daily_run_settings_url, params: {
        aicoo_daily_run_setting: {
          enabled: "0",
          run_hour: 9,
          run_minute: 30,
          timezone: "Asia/Tokyo",
          catch_up_enabled: "1",
          retry_until_success: "1",
          max_retry_per_day: 5
        }
      }

      assert_redirected_to admin_aicoo_daily_run_settings_url
      setting = AicooDailyRunSetting.current
      assert_not setting.enabled?
      assert_equal 9, setting.run_hour
      assert_equal 30, setting.run_minute
      assert_equal 5, setting.max_retry_per_day
    end
  end
end
