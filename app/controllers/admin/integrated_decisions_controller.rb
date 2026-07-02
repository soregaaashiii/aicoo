module Admin
  class IntegratedDecisionsController < ApplicationController
    def show
      @summary = Aicoo::IntegratedDecisionEngine.new.summary
      @latest_serp_run = @summary.serp_run
      @latest_daily_run = @summary.daily_run
      @unified_candidates = ActionCandidate
        .includes(:business)
        .where(generation_source: "integrated_decision")
        .order(created_at: :desc)
        .limit(20)
    end
  end
end
