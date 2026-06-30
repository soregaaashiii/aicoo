module Admin
  class PipelineE2eChecksController < ApplicationController
    def show
      @pipeline_run = selected_pipeline_run
      @result = Aicoo::PipelineE2eCheck.new(@pipeline_run).call
      @recent_failures = Aicoo::PipelineE2eCheck.failing_results(limit: 10)
    end

    def repair
      pipeline_run = AicooPipelineRun.find(params.expect(:pipeline_run_id))
      result = Aicoo::PipelineE2eCheck.repair!(
        pipeline_run:,
        action: params.expect(:repair_action)
      )
      redirect_to admin_pipeline_e2e_check_path(pipeline_run_id: pipeline_run.id),
                  notice: "E2E復旧を実行しました。現在の状態: #{result.overall_status}"
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to admin_pipeline_e2e_check_path(pipeline_run_id: params[:pipeline_run_id]),
                  alert: "E2E復旧に失敗しました: #{e.message}"
    end

    private

    def selected_pipeline_run
      return AicooPipelineRun.find(params[:pipeline_run_id]) if params[:pipeline_run_id].present?

      Aicoo::PipelineE2eCheck.default_run
    end
  end
end
