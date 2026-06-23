class CodexQualityChecksController < ApplicationController
  before_action :set_codex_quality_check, only: %i[show approve reject]

  def index
    @filter = params[:filter].presence
    @codex_quality_checks = filtered_scope.includes(auto_revision_task: :business).order(created_at: :desc).limit(100)
  end

  def show
  end

  def approve
    @codex_quality_check.approve!(approved_by: "owner", approval_note: params[:approval_note])
    redirect_to @codex_quality_check, notice: "Quality Gateを承認しました。Learning Loopへ反映できます。"
  end

  def reject
    @codex_quality_check.reject!(approved_by: "owner", approval_note: params[:approval_note])
    redirect_to @codex_quality_check, notice: "Quality Gateを却下しました。Learning Loop verified=falseとして扱います。"
  end

  private

  def set_codex_quality_check
    @codex_quality_check = CodexQualityCheck.find(params.expect(:id))
  end

  def filtered_scope
    scope = CodexQualityCheck.all
    return scope.where(approval_status: @filter) if @filter.in?(CodexQualityCheck::APPROVAL_STATUSES)
    return scope.where(result: @filter) if @filter.in?(CodexQualityCheck::RESULTS)

    scope
  end
end
