require "test_helper"

module Admin
  module AicooLab
    class SettingsControllerTest < ActionDispatch::IntegrationTest
      test "should get show" do
        get admin_aicoo_lab_setting_url
        assert_response :success
      end

      test "should update setting" do
        patch admin_aicoo_lab_setting_url, params: {
          aicoo_lab_setting: {
            monthly_budget_yen: 10_000,
            minimum_sample_pv: 2_000,
            hourly_cost_yen: 1_300,
            auto_generate_enabled: false,
            free_experiments_continue_after_budget: true
          }
        }

        assert_redirected_to admin_aicoo_lab_setting_url
        assert_equal 10_000, AicooLabSetting.current.monthly_budget_yen
      end
    end
  end
end
