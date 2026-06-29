module Owner
  class FocusController < ApplicationController
    def show
      @owner_focus_home = Aicoo::OwnerFocusHome.new.call
      @top_task = @owner_focus_home.top_task
      @ceo_sort_mode = ceo_sort_mode
      @owner_execution_queue_summary = Aicoo::OwnerExecutionQueueSummary.new.call
      @ceo_priority_ranking = Aicoo::CeoPriorityRanking.new(
        tasks: @owner_focus_home.focus_tasks,
        sort_mode: @ceo_sort_mode,
        queue_items: @owner_execution_queue_summary.skipped_items,
        deferred_task_keys: deferred_task_keys
      ).call
      @explore_daily_routine = Aicoo::ExploreDailyRoutine.new.call
      @opportunity_focus_item = opportunity_focus_item
      @owner_decision_summary = Aicoo::OwnerDecisionSummary.new.call
      @analysis_monitor = Aicoo::AnalysisMonitor.new.call
      @serp_scan_status = Aicoo::Serp::ScanStatus.new.call
      @business_auto_revision_summary = Aicoo::BusinessAutoRevisionSummary.new.call
      sync_pipeline_runs
      @stopped_pipeline_runs = AicooPipelineRun.stopped_for_owner.includes(:business, :idea_pipeline_item).recent.limit(5)
      @running_daily_run = AicooDailyRun.running.includes(:aicoo_daily_run_steps).recent.first
      @top_task_evidence = evidence_for_top_task
      @top_task_expansion = expansion_for_top_task
      @top_task_action_candidate = top_task_action_candidate
      @top_task_detail_path = top_task_detail_path
      @ceo_summary = Aicoo::CeoSummaryBuilder.new(
        task: @top_task,
        action_candidate: @top_task_action_candidate,
        opportunity: @opportunity_focus_item&.opportunity
      ).call
      @business_integration_health = Aicoo::BusinessIntegrationHealth.new.call
      @owner_home_summary = Aicoo::OwnerHomeSummary.new(
        owner_focus_home: @owner_focus_home,
        explore_daily_routine: @explore_daily_routine
      ).call
    end

    def defer
      key = params[:task_key].to_s
      session[:ceo_deferred_task_keys] = (deferred_task_keys + [ key ]).uniq if key.present?
      redirect_to owner_focus_path(sort: ceo_sort_mode), notice: "後でやるに移しました。"
    end

    def restore
      key = params[:task_key].to_s
      session[:ceo_deferred_task_keys] = deferred_task_keys - [ key ] if key.present?
      redirect_to owner_focus_path(sort: ceo_sort_mode), notice: "今日のランキングに戻しました。"
    end

    private

    def ceo_sort_mode
      mode = params[:sort].presence_in(Aicoo::CeoPriorityRanking::SORT_MODES)
      session[:ceo_priority_sort_mode] = mode if mode.present?
      mode || "recommended"
    end

    def deferred_task_keys
      Array(session[:ceo_deferred_task_keys]).compact_blank
    end

    def opportunity_focus_item
      return unless @top_task&.task_type == "opportunity_review"

      Aicoo::OpportunityFocusQueue.new.call.items.find do |item|
        item.opportunity.title == @top_task.title
      end
    end

    def evidence_for_top_task
      return @opportunity_focus_item.opportunity.metadata.to_h["evidence"] if @opportunity_focus_item

      top_task_action_candidate&.metadata.to_h["evidence"]
    end

    def expansion_for_top_task
      top_task_action_candidate&.metadata.to_h["action_expansion"]
    end

    def top_task_action_candidate
      return unless @top_task

      if @top_task.target_path.to_s.match?(%r{/action_candidates/\d+})
        id = @top_task.target_path.to_s.split("/").last
        ActionCandidate.find_by(id:)
      elsif @top_task.target_path.to_s.match?(%r{/action_executions/\d+})
        id = @top_task.target_path.to_s.split("/").last
        ActionExecution.find_by(id:)&.action_candidate
      end
    end

    def top_task_detail_path
      return unless @top_task
      return owner_opportunity_path(@opportunity_focus_item.opportunity) if @opportunity_focus_item

      if @top_task.target_path.to_s.match?(%r{/action_executions/\d+})
        @top_task.target_path
      elsif @top_task_action_candidate&.action_execution
        action_execution_path(@top_task_action_candidate.action_execution)
      else
        @top_task.target_path
      end
    end

    def sync_pipeline_runs
      IdeaPipelineItem.recent.limit(25).each { |item| Aicoo::PipelineEngine.new(item).call }
    end
  end
end
