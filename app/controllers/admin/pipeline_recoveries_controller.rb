module Admin
  class PipelineRecoveriesController < ApplicationController
    def create
      run = AicooPipelineRun.find(params.expect(:pipeline_run_id))
      action = params.expect(:recovery_action)
      log = Aicoo::PipelineRecoveryService.new(run, action:, source: "owner").call

      if log.success?
        redirect_back fallback_location: run.target_path, notice: "Pipeline復旧を実行しました: #{action}"
      else
        redirect_back fallback_location: run.target_path, alert: "Pipeline復旧に失敗しました: #{log.error_message}"
      end
    end
  end
end
