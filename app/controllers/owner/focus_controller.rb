module Owner
  class FocusController < ApplicationController
    def show
      @owner_focus_home = Aicoo::OwnerFocusHome.new.call
      @top_task = @owner_focus_home.top_task
      @explore_daily_routine = Aicoo::ExploreDailyRoutine.new.call
      @opportunity_focus_item = opportunity_focus_item
      @owner_execution_queue_summary = Aicoo::OwnerExecutionQueueSummary.new.call
      @owner_decision_summary = Aicoo::OwnerDecisionSummary.new.call
      @top_task_evidence = evidence_for_top_task
      @business_integration_health = Aicoo::BusinessIntegrationHealth.new.call
      @owner_home_summary = Aicoo::OwnerHomeSummary.new(
        owner_focus_home: @owner_focus_home,
        explore_daily_routine: @explore_daily_routine
      ).call
    end

    private

    def opportunity_focus_item
      return unless @top_task&.task_type == "opportunity_review"

      Aicoo::OpportunityFocusQueue.new.call.items.find do |item|
        item.opportunity.title == @top_task.title
      end
    end

    def evidence_for_top_task
      return @opportunity_focus_item.opportunity.metadata.to_h["evidence"] if @opportunity_focus_item
      return unless @top_task&.target_path.to_s.match?(%r{/action_candidates/\d+})

      id = @top_task.target_path.to_s.split("/").last
      ActionCandidate.find_by(id:)&.metadata.to_h["evidence"]
    end
  end
end
