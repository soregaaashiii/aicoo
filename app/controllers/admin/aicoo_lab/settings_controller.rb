module Admin
  module AicooLab
    class SettingsController < ApplicationController
      def show
        @setting = AicooLabSetting.current
      end

      def update
        @setting = AicooLabSetting.current

        if @setting.update(setting_params)
          redirect_to admin_aicoo_lab_setting_path, notice: "AICOO Lab setting was updated."
        else
          render :show, status: :unprocessable_content
        end
      end

      private

      def setting_params
        params.expect(
          aicoo_lab_setting: [
            :monthly_budget_yen, :minimum_sample_pv, :hourly_cost_yen,
            :auto_generate_enabled, :free_experiments_continue_after_budget
          ]
        )
      end
    end
  end
end
