module Owner
  class FocusController < ApplicationController
    def show
      @cron_health_summary = Aicoo::CronHealthDashboard.new.call.summary
      @traffic_channel_summary = Aicoo::TrafficChannels::Summary.call
      @serp_summary = Aicoo::Serp::Summary.call
      @system_statuses = %w[daily_run traffic traffic_serp render openai codex learning].index_with do |key|
        Aicoo::SystemStatusResolver.call(key)
      end
      @auto_revision_execution_summary = Aicoo::AutoRevisionExecutionSummary.new.call
      @codex_submission_summary = Aicoo::CodexSubmissionSummary.new.call
      @auto_build_summary = Aicoo::ResourceAwareAutoBuildSummary.new.call
      @new_business_candidate_board = Aicoo::NewBusinessCandidateBoard.call(limit: 3)
      @ceo_improvement_board = Aicoo::CeoModeBusinessImprovementBoard.new(
        deferred_task_keys:
      ).call
      @today_business_improvement = @ceo_improvement_board.today_one
    end

    def defer
      key = params[:task_key].to_s
      session[:ceo_deferred_task_keys] = (deferred_task_keys + [ key ]).uniq if key.present?
      redirect_to owner_focus_path, notice: "後でやるに移しました。"
    end

    def restore
      key = params[:task_key].to_s
      session[:ceo_deferred_task_keys] = deferred_task_keys - [ key ] if key.present?
      redirect_to owner_focus_path, notice: "今日のランキングに戻しました。"
    end

    private

    def deferred_task_keys
      Array(session[:ceo_deferred_task_keys]).compact_blank
    end
  end
end
