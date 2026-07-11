module Owner
  class DashboardController < ApplicationController
    def show
      @mode = params[:mode].presence_in(%w[balanced revenue learning]) || "balanced"
      @today_board = Aicoo::TodayActionBoard.new(
        mode: @mode,
        page: params[:home_actions_page],
        page_param: :home_actions_page
      ).call
      @dashboard_summary = DashboardSummaryService.new(owner_mode: @mode, current_mode: "ceo").call
      @owner_task_inbox = Aicoo::OwnerTaskInbox.new.call
      @owner_task_digest = Aicoo::OwnerTaskDigest.new(owner_task_inbox: @owner_task_inbox).call
      @owner_focus_home = Aicoo::OwnerFocusHome.new(owner_task_inbox: @owner_task_inbox).call
      @owner_task_completion_logs = OwnerTaskCompletionLog.recent.limit(3)
      @learning_loop_quality_report = Aicoo::LearningLoopQualityReport.new.call
      @learning_report_recommendations = Aicoo::LearningReportRecommendation.new.call
      @strategic_learning_report = Aicoo::StrategicLearningReport.new.call
      @opportunity_discovery_summary = Aicoo::OpportunityDiscoverySummary.new.call
      @discovery_source_performance_report = Aicoo::DiscoverySourcePerformanceReport.new.call
      @opportunity_focus_queue = Aicoo::OpportunityFocusQueue.new.call
      @explore_summary = Aicoo::ExploreSummary.new.call
      @explore_daily_routine = Aicoo::ExploreDailyRoutine.new.call
      @analysis_monitor = Aicoo::AnalysisMonitor.new.call
    end
  end
end
