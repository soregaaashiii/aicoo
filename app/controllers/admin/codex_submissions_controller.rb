module Admin
  class CodexSubmissionsController < ApplicationController
    before_action :set_codex_submission, only: %i[
      show
      mark_submitted
      mark_failed
      mark_completed
      retry
      update_tracking
      mark_merged
      mark_deployed
    ]

    def index
      @status_filter = params[:status].presence
      @business_id = params[:business_id].presence
      @project_folder = params[:project_folder].presence
      @risk_filter = params[:risk].presence
      @codex_submissions = filtered_scope
        .includes(:business, :auto_revision_task, :business_execution_profile)
        .recent
        .limit(100)
    end

    def show
    end

    def mark_submitted
      @codex_submission.mark_submitted!(payload: { "marked_by" => "owner", "source" => "codex_submission_detail" })
      redirect_to admin_codex_submission_path(@codex_submission), notice: "Codexへ手動送信済みとして記録しました。"
    end

    def mark_failed
      @codex_submission.mark_failed!(params[:error_message].presence || "Ownerが送信失敗として記録しました。")
      redirect_to admin_codex_submission_path(@codex_submission), notice: "Codex手動送信失敗として記録しました。"
    end

    def mark_completed
      @codex_submission.mark_completed!(payload: { "marked_by" => "owner", "source" => "codex_submission_detail" })
      redirect_to admin_codex_submission_path(@codex_submission), notice: "Codex完了として記録しました。"
    end

    def retry
      @codex_submission.retry!
      redirect_back fallback_location: admin_codex_connection_path, notice: "Codex手動送信を再試行待ちに戻しました。"
    end

    def update_tracking
      @codex_submission.update_tracking!(tracking_params.merge(tracking_updated_by: "owner"))
      redirect_back fallback_location: admin_codex_connection_path, notice: "PR追跡情報を更新しました。"
    end

    def mark_merged
      @codex_submission.mark_merged!
      redirect_back fallback_location: admin_codex_connection_path, notice: "PRをmerge済みとして記録しました。"
    end

    def mark_deployed
      @codex_submission.mark_deployed!
      redirect_back fallback_location: admin_codex_connection_path, notice: "deploy済みとして記録しました。"
    end

    private

    def set_codex_submission
      @codex_submission = CodexSubmission.find(params.expect(:id))
    end

    def filtered_scope
      scope = CodexSubmission.all
      scope = scope.where(status: @status_filter) if @status_filter.present? && @status_filter.in?(CodexSubmission::STATUSES)
      scope = scope.where(business_id: @business_id) if @business_id.present?
      scope = scope.where(project_folder: @project_folder) if @project_folder.present?
      if @risk_filter.present? && @risk_filter.in?(AutoRevisionTask::RISK_LEVELS)
        scope = scope.joins(:auto_revision_task).where(auto_revision_tasks: { risk_level: @risk_filter })
      end
      scope
    end

    def tracking_params
      params.expect(
        codex_submission: [
          :pull_request_url,
          :pr_status,
          :review_status,
          :ci_status,
          :test_result,
          :merge_status,
          :deploy_status
        ]
      )
    end
  end
end
