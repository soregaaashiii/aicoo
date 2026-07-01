module Admin
  class ExternalCommitImportsController < ApplicationController
    def new
      @businesses = Business.real_businesses.order(:name)
      @business = Business.find_by(id: params[:business_id])
      @action_candidate = ActionCandidate.find_by(id: params[:action_candidate_id])
      @auto_revision_task = AutoRevisionTask.find_by(id: params[:auto_revision_task_id])
    end

    def create
      result = Aicoo::ExternalCommitImporter.new(external_commit_import_params).call
      redirect_to result.action_result,
                  notice: "外部commitをAICOOへ取り込みました。ActionResultとActivity Logに反映しました。"
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: new_admin_external_commit_import_path,
                    alert: "外部commitを取り込めませんでした: #{e.message}"
    end

    private

    def external_commit_import_params
      params.expect(
        external_commit_import: [
          :business_id,
          :action_candidate_id,
          :auto_revision_task_id,
          :repository,
          :commit_sha,
          :changed_files,
          :result_summary,
          :test_result,
          :actual_revenue_yen,
          :actual_profit_yen,
          :executed_at
        ]
      )
    end
  end
end
