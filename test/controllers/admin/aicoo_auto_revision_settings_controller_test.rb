require "test_helper"

class Admin::AicooAutoRevisionSettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows auto revision setting" do
    AicooAutoRevisionSetting.current

    get admin_aicoo_auto_revision_settings_url

    assert_response :success
    assert_includes response.body, "Auto Revision自動キュー設定"
    assert_includes response.body, "自動キュー生成"
    assert_includes response.body, "前回生成"
  end

  test "updates auto revision setting" do
    patch admin_aicoo_auto_revision_settings_url, params: {
      aicoo_auto_revision_setting: {
        enabled: "1",
        max_tasks_per_run: "3",
        minimum_final_score: "2500",
        allow_medium_risk: "0"
      }
    }

    assert_redirected_to admin_aicoo_auto_revision_settings_url
    setting = AicooAutoRevisionSetting.current
    assert_equal true, setting.enabled?
    assert_equal 3, setting.max_tasks_per_run
    assert_equal 2_500.to_d, setting.minimum_final_score
    assert_equal false, setting.allow_medium_risk?
  end
end
