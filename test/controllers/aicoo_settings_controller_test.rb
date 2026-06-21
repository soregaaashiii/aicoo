require "test_helper"

class AicooSettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows current auto queue setting" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: true)

    get aicoo_setting_url

    assert_response :success
    assert_includes response.body, "AICOO設定"
    assert_includes response.body, "データ整備タスク自動キュー投入"
    assert_includes response.body, "自動投入ON"
  end

  test "updates auto queue setting on" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: false)

    patch aicoo_setting_url, params: {
      aicoo_setting: { auto_queue_data_preparation_tasks: "1" }
    }

    assert_redirected_to aicoo_setting_url
    assert AicooSetting.current.reload.auto_queue_data_preparation_tasks?
  end

  test "updates auto queue setting off" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: true)

    patch aicoo_setting_url, params: {
      aicoo_setting: { auto_queue_data_preparation_tasks: "0" }
    }

    assert_redirected_to aicoo_setting_url
    assert_not AicooSetting.current.reload.auto_queue_data_preparation_tasks?
  end
end
